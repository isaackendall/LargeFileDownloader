import Foundation

enum CommandLocator {
    static func find(_ executable: String) -> String? {
        let envPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        let fallbackPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let searchPaths = envPaths + fallbackPaths

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
