import AppKit
import Foundation

enum FolderPicker {
    @MainActor
    static func chooseFolder(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: path)
        panel.prompt = "Choose"

        let response = panel.runModal()
        return response == .OK ? panel.url?.path : nil
    }

    static func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
