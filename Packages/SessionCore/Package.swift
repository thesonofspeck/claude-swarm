// swift-tools-version: 6.0
import PackageDescription

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
        .target(name: "SessionCore", dependencies: ["PersistenceKit", "GitKit", "AgentBootstrap"]),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"])
    ]
)
