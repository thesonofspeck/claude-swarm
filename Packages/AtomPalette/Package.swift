// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AtomPalette",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AtomPalette", targets: ["AtomPalette"])
    ],
    targets: [
        .target(name: "AtomPalette"),
        .testTarget(name: "AtomPaletteTests", dependencies: ["AtomPalette"])
    ]
)
