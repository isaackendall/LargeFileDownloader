import XCTest
@testable import LargeFileDownloader

final class RedirectResolverTests: XCTestCase {
    func testUnwrapsEmbeddedDownloadURLFromWrapperPage() {
        let wrapperURL = URL(string: "https://downloader.example.com/?url=https%3A%2F%2Fuploads.example.com%2Fcompany%2Fproject%2FSheds_G2mm.e57")!

        let unwrapped = RedirectResolver.unwrapDownloadURL(from: wrapperURL)

        XCTAssertEqual(
            unwrapped?.absoluteString,
            "https://uploads.example.com/company/project/Sheds_G2mm.e57"
        )
    }

    func testLeavesDirectFileURLAlone() {
        let directURL = URL(string: "https://example.com/files/archive.zip")!

        XCTAssertNil(RedirectResolver.unwrapDownloadURL(from: directURL))
    }
}
