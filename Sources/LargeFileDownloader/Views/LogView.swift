import SwiftUI

struct LogView: View {
    let entries: [DownloadLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if entries.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(entries) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(2)
            }
            .onChange(of: entries.count) { _, _ in
                guard let last = entries.last else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: DownloadLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Text(entry.message)
                .font(.callout.monospaced())
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var backgroundColor: Color {
        switch entry.kind {
        case .info: return Color.black.opacity(0.03)
        case .command: return Color.blue.opacity(0.08)
        case .success: return Color.green.opacity(0.10)
        case .warning: return Color.orange.opacity(0.10)
        case .error: return Color.red.opacity(0.10)
        }
    }

    private var color: Color {
        switch entry.kind {
        case .info: return .primary
        case .command: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
