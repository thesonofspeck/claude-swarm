// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrewInstaller",
    platforms: [.macOS("26.0")],
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
