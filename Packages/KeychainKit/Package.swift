// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "KeychainKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "KeychainKit", targets: ["KeychainKit"])
    ],
    targets: [
        .target(name: "KeychainKit", swiftSettings: swift6),
        .testTarget(name: "KeychainKitTests", dependencies: ["KeychainKit"], swiftSettings: swift6)
    ]
)
