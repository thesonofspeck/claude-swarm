// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AtomPalette",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "AtomPalette", targets: ["AtomPalette"])
    ],
    targets: [
        .target(name: "AtomPalette"),
        .testTarget(name: "AtomPaletteTests", dependencies: ["AtomPalette"])
    ]
)
