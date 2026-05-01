// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "ToolDetector",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ToolDetector", targets: ["ToolDetector"])
    ],
    targets: [
        .target(name: "ToolDetector", swiftSettings: swift6),
        .testTarget(name: "ToolDetectorTests", dependencies: ["ToolDetector"], swiftSettings: swift6)
    ]
)
