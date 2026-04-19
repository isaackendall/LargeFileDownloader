// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LargeFileDownloader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LargeFileDownloader",
            targets: ["LargeFileDownloader"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LargeFileDownloader",
            path: "Sources/LargeFileDownloader"
        )
    ]
)
