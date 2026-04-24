import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(DownloaderViewModel.self) private var model
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case sourceURL
        case outputFilename
    }

    private var configBinding: Binding<DownloadConfiguration> {
        Binding(
            get: { model.configuration },
            set: { model.configuration = $0 }
        )
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    HStack(alignment: .top, spacing: 18) {
                        controlColumn
                            .frame(maxWidth: 470)

                        logColumn
                    }
                }
                .padding(22)
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.10),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Large File Downloader")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("A polished local macOS transfer window for aria2c downloads.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            StatusBadge(status: model.status)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "Source", subtitle: "Paste a redirecting link, choose a folder, and set a name if you want one.") {
                VStack(alignment: .leading, spacing: 14) {
                    labeledTextField(
                        title: "Download URL",
                        placeholder: "https://example.com/file",
                        text: configBinding.sourceURLText,
                        field: .sourceURL
                    )

                    rowWithButton(title: "Destination Folder", value: model.configuration.destinationFolder, buttonTitle: "Choose Folder") {
                        model.chooseFolder()
                    }

                    outputFilenameField
                }
            }

            SectionCard(title: "Transfer Options", subtitle: "Tune concurrency and whether the Mac should stay awake during long downloads.") {
                VStack(alignment: .leading, spacing: 14) {
                    stepperRow(title: "Connections", value: configBinding.connections, range: 1...32)
                    stepperRow(title: "Splits", value: configBinding.splits, range: 1...32)

                    Toggle("Resolve final URL before download", isOn: configBinding.resolveBeforeDownload)
                    Toggle("Keep Mac awake during download", isOn: configBinding.keepMacAwake)
                }
            }

            SectionCard(title: "Actions", subtitle: "Start, stop, or open the destination folder.") {
                HStack(spacing: 12) {
                    PrimaryButton(title: "Start Download") {
                        model.startDownload()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    SecondaryButton(title: "Stop") {
                        model.stopDownload()
                    }
                    .disabled(!model.canStop)

                    SecondaryButton(title: "Open Folder") {
                        model.openFolder()
                    }
                }
            }

            SectionCard(title: "Progress", subtitle: "Live percentage from aria2c.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.downloadProgressText)
                            .font(.headline)
                            .monospacedDigit()

                        Spacer()

                        Text(model.status.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.downloadProgress, total: 1)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("Estimated time remaining")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(model.estimatedTimeRemainingText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }

                    if model.status == .running && !model.didReceiveProgressUpdate {
                        Text("Waiting for aria2c to emit its first progress summary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var logColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "", subtitle: "") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live Log")
                                .font(.headline)

                            Text("The latest aria2c output stays visible here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        SecondaryButton(title: "Copy Log") {
                            model.copyLog()
                        }
                    }

                    LogView(entries: model.logs)
                        .frame(minHeight: 340)
                }
            }
        }
    }

    private var outputFilenameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output Filename")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Leave blank to use the file name from the URL", text: configBinding.outputFilename)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .outputFilename)
                    .onSubmit {
                        focusedField = nil
                    }

                if focusedField == .outputFilename {
                    Button("Done") {
                        focusedField = nil
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(model.filenamePreviewNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func labeledTextField(title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
                .onSubmit {
                    focusedField = nil
                }
        }
    }

    private func rowWithButton(title: String, value: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            HStack(spacing: 10) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 10)

                Button(buttonTitle, action: action)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty || !subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.headline)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }
}

private struct StatusBadge: View {
    let status: DownloadStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.headline)
                    .font(.headline)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .ready: return .secondary
        case .resolving, .preparing: return .orange
        case .running: return .green
        case .stopping: return .yellow
        case .finished: return .green
        case .failed: return .red
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
    }
}

private struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}
