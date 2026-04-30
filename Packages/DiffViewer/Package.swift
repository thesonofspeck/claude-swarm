// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiffViewer",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DiffViewer", targets: ["DiffViewer"])
    ],
    dependencies: [
        .package(path: "../GitKit"),
        .package(path: "../AtomPalette"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0")
    ],
    targets: [
        .target(name: "DiffViewer", dependencies: ["GitKit", "AtomPalette", "Splash"]),
        .testTarget(name: "DiffViewerTests", dependencies: ["DiffViewer"])
    ]
)
