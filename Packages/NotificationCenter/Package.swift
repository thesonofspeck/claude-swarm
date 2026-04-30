// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSwarmNotifications",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeSwarmNotifications", targets: ["ClaudeSwarmNotifications"])
    ],
    targets: [
        .target(
            name: "ClaudeSwarmNotifications",
            path: "Sources/NotificationCenter"
        ),
        .testTarget(
            name: "ClaudeSwarmNotificationsTests",
            dependencies: ["ClaudeSwarmNotifications"],
            path: "Tests/NotificationCenterTests"
        )
    ]
)
