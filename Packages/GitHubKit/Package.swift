// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "GitHubKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GitHubKit", targets: ["GitHubKit"])
    ],
    dependencies: [
        .package(path: "../GitKit")
    ],
    targets: [
        .target(name: "GitHubKit", dependencies: ["GitKit"], swiftSettings: swift6),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit"], swiftSettings: swift6)
    ]
)
