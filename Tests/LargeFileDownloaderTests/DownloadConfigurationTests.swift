import XCTest
@testable import LargeFileDownloader

final class DownloadConfigurationTests: XCTestCase {
    func testCustomFilenameWithoutExtensionKeepsSourceFileType() {
        var configuration = DownloadConfiguration()
        configuration.outputFilename = "RailwayBridge"

        let filename = configuration.effectiveFilename(for: URL(string: "https://example.com/source/original.e57")!)

        XCTAssertEqual(filename, "RailwayBridge.e57")
    }

    func testCustomFilenameWithExtensionIsLeftAlone() {
        var configuration = DownloadConfiguration()
        configuration.outputFilename = "RailwayBridge.las"

        let filename = configuration.effectiveFilename(for: URL(string: "https://example.com/source/original.e57")!)

        XCTAssertEqual(filename, "RailwayBridge.las")
    }

    func testAria2ArgumentsUsePreservedExtension() {
        var configuration = DownloadConfiguration()
        configuration.outputFilename = "RailwayBridge"

        let arguments = configuration.aria2Arguments(for: URL(string: "https://example.com/source/original.e57")!)

        XCTAssertTrue(arguments.contains("--out=RailwayBridge.e57"))
    }

    func testFilenamePreviewReportsResolvedFileTypeWhenAvailable() {
        var configuration = DownloadConfiguration()
        configuration.outputFilename = "RailwayBridge"

        let filename = configuration.filenamePreview(for: URL(string: "https://example.com/source/original.e57")!)

        XCTAssertEqual(filename, "RailwayBridge.e57")
        XCTAssertFalse(configuration.filenamePreviewNeedsResolvedURL(for: URL(string: "https://example.com/source/original.e57")!))
    }

    func testFilenamePreviewNotesWhenExtensionNeedsFinalURL() {
        var configuration = DownloadConfiguration()
        configuration.outputFilename = "RailwayBridge"

        XCTAssertEqual(configuration.filenamePreview(for: URL(string: "https://links.example.com/click?id=123")!), "RailwayBridge")
        XCTAssertTrue(configuration.filenamePreviewNeedsResolvedURL(for: URL(string: "https://links.example.com/click?id=123")!))
    }
}
