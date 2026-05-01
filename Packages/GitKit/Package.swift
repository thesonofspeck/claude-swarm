// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "GitKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GitKit", targets: ["GitKit"])
    ],
    targets: [
        .target(name: "GitKit", swiftSettings: swift6),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"], swiftSettings: swift6)
    ]
)
