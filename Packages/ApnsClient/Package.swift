// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "ApnsClient",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ApnsClient", targets: ["ApnsClient"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "ApnsClient", dependencies: ["KeychainKit"], swiftSettings: swift6),
        .testTarget(name: "ApnsClientTests", dependencies: ["ApnsClient"], swiftSettings: swift6)
    ]
)
