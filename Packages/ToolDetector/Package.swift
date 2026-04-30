// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolDetector",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ToolDetector", targets: ["ToolDetector"])
    ],
    targets: [
        .target(name: "ToolDetector"),
        .testTarget(name: "ToolDetectorTests", dependencies: ["ToolDetector"])
    ]
)
