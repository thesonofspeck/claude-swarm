// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToolDetector",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ToolDetector", targets: ["ToolDetector"])
    ],
    targets: [
        .target(name: "ToolDetector"),
        .testTarget(name: "ToolDetectorTests", dependencies: ["ToolDetector"])
    ]
)
