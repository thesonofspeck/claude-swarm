// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    dependencies: [
        .package(path: "../KeychainKit"),
        .package(path: "../PersistenceKit"),
        .package(path: "../GitKit"),
        .package(path: "../WrikeKit"),
        .package(path: "../GitHubKit"),
        .package(path: "../SessionCore"),
        .package(path: "../MemoryService"),
        .package(path: "../NotificationCenter"),
        .package(path: "../AgentBootstrap"),
        .package(path: "../PairingProtocol"),
        .package(path: "../PairingService"),
        .package(path: "../ApnsClient"),
        .package(path: "../SleepGuard"),
        .package(path: "../ToolDetector"),
        .package(path: "../BrewInstaller"),
        .package(path: "../LibraryKit")
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: [
                "KeychainKit",
                "PersistenceKit",
                "GitKit",
                "WrikeKit",
                "GitHubKit",
                "SessionCore",
                "MemoryService",
                .product(name: "ClaudeSwarmNotifications", package: "NotificationCenter"),
                "AgentBootstrap",
                "PairingProtocol",
                "PairingService",
                "ApnsClient",
                "SleepGuard",
                "ToolDetector",
                "BrewInstaller",
                "LibraryKit"
            ]
        ),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"])
    ]
)
