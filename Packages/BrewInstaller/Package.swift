// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrewInstaller",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrewInstaller", targets: ["BrewInstaller"])
    ],
    dependencies: [
        .package(path: "../ToolDetector")
    ],
    targets: [
        .target(name: "BrewInstaller", dependencies: ["ToolDetector"])
    ]
)
