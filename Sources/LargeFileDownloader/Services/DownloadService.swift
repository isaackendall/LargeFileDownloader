import Foundation

final class DownloadSession: @unchecked Sendable {
    private let downloadProcess: Process
    private var caffeinateProcess: Process?
    private let outputPipe: Pipe
    private let outputBuffer = LineBuffer()
    private let onLine: @Sendable (DownloadLogEntry) -> Void
    private let onProgress: @Sendable (Double) -> Void
    private var didStop = false

    init(
        downloadProcess: Process,
        outputPipe: Pipe,
        onLine: @escaping @Sendable (DownloadLogEntry) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.downloadProcess = downloadProcess
        self.outputPipe = outputPipe
        self.onLine = onLine
        self.onProgress = onProgress
    }

    func setCaffeinateProcess(_ process: Process?) {
        caffeinateProcess = process
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        downloadProcess.terminate()
        caffeinateProcess?.terminate()
    }

    func attachTerminationHandler(_ handler: @escaping @Sendable (Int32) -> Void) {
        downloadProcess.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.finishOutput()
            handler(self.downloadProcess.terminationStatus)
        }
    }

    func feedOutput(_ data: Data) {
        for line in outputBuffer.append(data) {
            onLine(DownloadLogEntry(date: Date(), kind: .info, message: line))
            if let progress = Self.extractProgress(from: line) {
                onProgress(progress)
            }
        }
    }

    func finishOutput() {
        if let line = outputBuffer.finish(), !line.isEmpty {
            onLine(DownloadLogEntry(date: Date(), kind: .info, message: line))
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
    }

    private static func extractProgress(from line: String) -> Double? {
        guard let range = line.range(of: #"\((\d{1,3})%\)"#, options: .regularExpression) else {
            return nil
        }

        let percentText = line[range].trimmingCharacters(in: CharacterSet(charactersIn: "()%"))
        guard let percent = Double(percentText), (0...100).contains(percent) else {
            return nil
        }

        return percent / 100.0
    }
}

struct DownloadService {
    func start(
        executablePath: String,
        configuration: DownloadConfiguration,
        resolvedURL: URL,
        keepAwake: Bool,
        onLine: @escaping @Sendable (DownloadLogEntry) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws -> DownloadSession {
        let downloadProcess = Process()
        downloadProcess.executableURL = URL(fileURLWithPath: executablePath)
        downloadProcess.arguments = configuration.aria2Arguments(for: resolvedURL)

        let outputPipe = Pipe()
        downloadProcess.standardOutput = outputPipe
        downloadProcess.standardError = outputPipe

        let session = DownloadSession(
            downloadProcess: downloadProcess,
            outputPipe: outputPipe,
            onLine: onLine,
            onProgress: onProgress
        )

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            session.feedOutput(data)
        }

        try downloadProcess.run()

        if keepAwake {
            let caffeine = Process()
            caffeine.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            caffeine.arguments = ["-di", "-w", String(downloadProcess.processIdentifier)]
            do {
                try caffeine.run()
                session.setCaffeinateProcess(caffeine)
            } catch {
                onLine(DownloadLogEntry(date: Date(), kind: .warning, message: "caffeinate could not start; the download will continue without sleep prevention."))
            }
        }

        return session
    }
}
