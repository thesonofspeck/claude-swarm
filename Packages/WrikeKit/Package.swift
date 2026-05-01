// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "WrikeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WrikeKit", targets: ["WrikeKit"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "WrikeKit", dependencies: ["KeychainKit"], swiftSettings: swift6),
        .testTarget(name: "WrikeKitTests", dependencies: ["WrikeKit"], swiftSettings: swift6)
    ]
)
