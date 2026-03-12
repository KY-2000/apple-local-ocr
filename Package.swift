// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "apple-local-ocr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppleLocalOCRKit", targets: ["AppleLocalOCRKit"]),
        .executable(name: "apple-local-ocr", targets: ["AppleLocalOCRCLI"])
    ],
    targets: [
        .target(
            name: "AppleLocalOCRKit",
            path: "Sources/AppleLocalOCRKit"),
        .executableTarget(
            name: "AppleLocalOCRCLI",
            dependencies: ["AppleLocalOCRKit"],
            path: "Sources/apple-local-ocr"),
        .testTarget(
            name: "AppleLocalOCRTests",
            dependencies: ["AppleLocalOCRKit"],
            path: "Tests/AppleLocalOCRTests")
    ]
)
