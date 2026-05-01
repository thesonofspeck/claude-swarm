// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "SessionCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SessionCore", targets: ["SessionCore"])
    ],
    dependencies: [
        .package(path: "../PersistenceKit"),
        .package(path: "../GitKit"),
        .package(path: "../AgentBootstrap")
    ],
    targets: [
        .target(name: "SessionCore", dependencies: ["PersistenceKit", "GitKit", "AgentBootstrap"], swiftSettings: swift6),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"], swiftSettings: swift6)
    ]
)
