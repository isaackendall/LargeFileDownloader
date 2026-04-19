import Foundation

enum ShellQuote {
    static func joined(_ command: String, _ arguments: [String]) -> String {
        ([command] + arguments).map(quote).joined(separator: " ")
    }

    static func quote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./_-"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
