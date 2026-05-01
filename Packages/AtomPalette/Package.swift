// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "AtomPalette",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "AtomPalette", targets: ["AtomPalette"])
    ],
    targets: [
        .target(name: "AtomPalette", swiftSettings: swift6),
        .testTarget(name: "AtomPaletteTests", dependencies: ["AtomPalette"], swiftSettings: swift6)
    ]
)
