import Foundation

enum DownloadStatus: Equatable {
    case ready
    case resolving
    case preparing
    case running
    case stopping
    case finished
    case failed(String)

    var headline: String {
        switch self {
        case .ready: return "Ready"
        case .resolving: return "Resolving URL"
        case .preparing: return "Preparing transfer"
        case .running: return "Downloading"
        case .stopping: return "Stopping"
        case .finished: return "Download finished"
        case .failed: return "Download failed"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            return "Paste a URL and choose a destination folder."
        case .resolving:
            return "Checking the final file URL before launch."
        case .preparing:
            return "Building the aria2c command."
        case .running:
            return "aria2c is active and streaming logs."
        case .stopping:
            return "Sending a stop request to the active process."
        case .finished:
            return "The transfer ended successfully."
        case .failed(let message):
            return message
        }
    }
}

enum DownloadLogKind {
    case info
    case command
    case success
    case warning
    case error

    var tint: String {
        switch self {
        case .info: return "secondary"
        case .command: return "blue"
        case .success: return "green"
        case .warning: return "orange"
        case .error: return "red"
        }
    }

    var label: String {
        switch self {
        case .info: return "info"
        case .command: return "command"
        case .success: return "success"
        case .warning: return "warning"
        case .error: return "error"
        }
    }
}

struct DownloadLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let kind: DownloadLogKind
    let message: String
}

struct DownloadConfiguration: Equatable {
    var sourceURLText = ""
    var destinationFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    var outputFilename = ""
    var connections = 8
    var splits = 8
    var resolveBeforeDownload = true
    var keepMacAwake = true

    func validatedSourceURL() throws -> URL {
        let trimmed = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw DownloadValidationError.invalidURL
        }
        return url
    }

    func validatedDestinationFolder() throws -> URL {
        let url = URL(fileURLWithPath: destinationFolder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DownloadValidationError.invalidFolder
        }
        return url
    }

    func effectiveFilename(for url: URL) -> String {
        let trimmed = outputFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Self.filenamePreservingExtension(trimmed, sourceURL: url)
        }

        if let lastComponent = url.pathComponents.last, !lastComponent.isEmpty, lastComponent != "/" {
            return lastComponent
        }

        return "download.bin"
    }

    func filenamePreview(for url: URL?) -> String {
        guard let url else {
            let trimmed = outputFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "download.bin" : trimmed
        }

        return effectiveFilename(for: url)
    }

    func filenamePreviewNeedsResolvedURL(for url: URL?) -> Bool {
        let trimmed = outputFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              URL(fileURLWithPath: trimmed).pathExtension.isEmpty else {
            return false
        }

        guard let url else {
            return true
        }

        return url.pathExtension.isEmpty
    }

    private static func filenamePreservingExtension(_ filename: String, sourceURL: URL) -> String {
        let sourceExtension = sourceURL.pathExtension
        guard !sourceExtension.isEmpty else {
            return filename
        }

        let customExtension = URL(fileURLWithPath: filename).pathExtension
        guard customExtension.isEmpty else {
            return filename
        }

        return "\(filename).\(sourceExtension)"
    }

    func aria2Arguments(for resolvedURL: URL) -> [String] {
        let filename = effectiveFilename(for: resolvedURL)
        return [
            "-c",
            "-x\(connections)",
            "-s\(splits)",
            "--file-allocation=none",
            "--console-log-level=notice",
            "--show-console-readout=true",
            "--summary-interval=1",
            "--dir=\(destinationFolder)",
            "--out=\(filename)",
            resolvedURL.absoluteString
        ]
    }
}

enum DownloadValidationError: LocalizedError {
    case invalidURL
    case invalidFolder
    case missingAria2

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http:// or https:// URL."
        case .invalidFolder:
            return "Choose an existing destination folder."
        case .missingAria2:
            return "aria2c was not found on PATH."
        }
    }
}
