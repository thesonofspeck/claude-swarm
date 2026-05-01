// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "LibraryKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LibraryKit", targets: ["LibraryKit"])
    ],
    dependencies: [
        .package(path: "../GitKit"),
        .package(path: "../AgentBootstrap")
    ],
    targets: [
        .target(name: "LibraryKit", dependencies: ["GitKit", "AgentBootstrap"], swiftSettings: swift6),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"], swiftSettings: swift6)
    ]
)
