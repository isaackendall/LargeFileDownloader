import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DownloaderViewModel {
    var configuration = DownloadConfiguration()
    var logs: [DownloadLogEntry] = []
    var status: DownloadStatus = .ready
    var resolvedURLText = ""
    var commandText: String { runningCommandText ?? commandPreviewText() }
    var estimatedTimeRemainingText: String { estimatedTimeRemaining() }
    var filenamePreviewText: String { configuration.filenamePreview(for: filenamePreviewURL()) }
    var filenamePreviewNote: String {
        if configuration.filenamePreviewNeedsResolvedURL(for: filenamePreviewURL()) {
            return "File type will be kept after the final URL resolves."
        }

        return "Will save as \(filenamePreviewText)"
    }
    var canStop = false
    var downloadProgress = 0.0
    var downloadProgressText = "0%"
    var didReceiveProgressUpdate = false

    private let redirectResolver = RedirectResolver()
    private let downloadService = DownloadService()
    private var session: DownloadSession?
    private var runningCommandText: String?
    private var downloadStartedAt: Date?

    init() {
        addLog(kind: .info, "Paste a large-file URL, choose a folder, and start the transfer.")
    }

    func chooseFolder() {
        if let folder = FolderPicker.chooseFolder(startingAt: configuration.destinationFolder) {
            configuration.destinationFolder = folder
            addLog(kind: .info, "Destination folder set to \(folder)")
        }
    }

    func openFolder() {
        FolderPicker.openFolder(configuration.destinationFolder)
    }

    func copyLog() {
        guard !logs.isEmpty else {
            addLog(kind: .warning, "No log entries are available yet.")
            return
        }

        let text = logs.map { entry in
            "[\(Self.logDateFormatter.string(from: entry.date))] [\(entry.kind.label)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        addLog(kind: .success, "Log copied to the clipboard.")
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandText, forType: .string)
        addLog(kind: .success, "Command copied to the clipboard.")
    }

    func copyResolvedURL() {
        guard !resolvedURLText.isEmpty else {
            addLog(kind: .warning, "No resolved URL is available yet.")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resolvedURLText, forType: .string)
        addLog(kind: .success, "Resolved URL copied to the clipboard.")
    }

    func startDownload() {
        guard session == nil else {
            addLog(kind: .warning, "A download is already running.")
            return
        }

        Task {
            await startDownloadTask()
        }
    }

    func stopDownload() {
        guard let session else { return }
        status = .stopping
        addLog(kind: .warning, "Stopping the active download...")
        session.stop()
    }

    func clearLog() {
        logs.removeAll()
    }

    private func startDownloadTask() async {
        do {
            resetProgress()
            downloadStartedAt = .now
            status = .preparing
            addLog(kind: .info, "Validating the source URL and destination folder...")

            let sourceURL = try configuration.validatedSourceURL()
            _ = try configuration.validatedDestinationFolder()

            let finalURL: URL
            if configuration.resolveBeforeDownload {
                status = .resolving
                addLog(kind: .info, "Resolving redirects before launch...")
                finalURL = try await redirectResolver.resolve(sourceURL)
                resolvedURLText = finalURL.absoluteString
                addLog(kind: .success, "Resolved URL: \(resolvedURLText)")
            } else {
                finalURL = sourceURL
                resolvedURLText = sourceURL.absoluteString
            }

            let aria2c = try locateAria2c()
            runningCommandText = ShellQuote.joined(URL(fileURLWithPath: aria2c).lastPathComponent, configuration.aria2Arguments(for: finalURL))

            status = .running
            canStop = true
            addLog(kind: .command, commandText)

            session = try downloadService.start(
                executablePath: aria2c,
                configuration: configuration,
                resolvedURL: finalURL,
                keepAwake: configuration.keepMacAwake,
                onLine: { [weak self] entry in
                    Task { @MainActor in
                        self?.logs.append(entry)
                    }
                },
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.updateProgress(progress)
                    }
                }
            )

            session?.attachTerminationHandler { [weak self] exitCode in
                Task { @MainActor in
                    guard let self else { return }
                    self.canStop = false
                    self.session = nil
                    self.runningCommandText = nil
                    if exitCode == 0 {
                        self.updateProgress(1.0)
                        self.status = .finished
                        self.addLog(kind: .success, "Download completed successfully.")
                    } else {
                        self.status = .failed("aria2c exited with code \(exitCode).")
                        self.addLog(kind: .error, "aria2c exited with code \(exitCode).")
                    }
                }
            }
        } catch {
            session = nil
            canStop = false
            runningCommandText = nil
            status = .failed(error.localizedDescription)
            addLog(kind: .error, error.localizedDescription)
            resetProgress()
        }
    }

    private func locateAria2c() throws -> String {
        guard let aria2c = CommandLocator.find("aria2c") else {
            throw DownloadValidationError.missingAria2
        }
        return aria2c
    }

    private func commandPreviewText(using url: URL? = nil) -> String {
        let effectiveURL: URL
        if let url {
            effectiveURL = url
        } else if let resolved = URL(string: resolvedURLText) {
            effectiveURL = resolved
        } else if let source = try? configuration.validatedSourceURL() {
            effectiveURL = source
        } else {
            return "aria2c"
        }

        return ShellQuote.joined("aria2c", configuration.aria2Arguments(for: effectiveURL))
    }

    private func filenamePreviewURL() -> URL? {
        if let resolved = URL(string: resolvedURLText) {
            return resolved
        }

        return try? configuration.validatedSourceURL()
    }

    private func addLog(kind: DownloadLogKind, _ message: String) {
        logs.append(DownloadLogEntry(date: .now, kind: kind, message: message))
    }

    private func resetProgress() {
        downloadProgress = 0
        downloadProgressText = "0%"
        didReceiveProgressUpdate = false
        downloadStartedAt = nil
    }

    private func updateProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        downloadProgress = clamped
        downloadProgressText = "\(Int((clamped * 100).rounded()))%"
        didReceiveProgressUpdate = true
    }

    private func estimatedTimeRemaining() -> String {
        guard status == .running else { return "—" }
        guard let startedAt = downloadStartedAt, downloadProgress > 0, downloadProgress < 1 else {
            return "Calculating..."
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed.isFinite, elapsed > 0 else { return "Calculating..." }

        let remainingSeconds = max(0, elapsed * (1 - downloadProgress) / downloadProgress)
        return Self.durationFormatter.string(from: remainingSeconds) ?? "Calculating..."
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}
