import Foundation

final class LineBuffer {
    private var storage = ""

    func append(_ data: Data) -> [String] {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else {
            return []
        }

        storage += chunk
        return drainLines()
    }

    func finish() -> String? {
        let trimmed = storage.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.removeAll(keepingCapacity: false)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func drainLines() -> [String] {
        var lines: [String] = []
        while let range = storage.range(of: "\n") {
            let line = String(storage[..<range.lowerBound]).trimmingCharacters(in: .newlines)
            storage.removeSubrange(..<range.upperBound)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
