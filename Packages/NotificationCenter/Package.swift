// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "ClaudeSwarmNotifications",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ClaudeSwarmNotifications", targets: ["ClaudeSwarmNotifications"])
    ],
    targets: [
        .target(
            name: "ClaudeSwarmNotifications",
            path: "Sources/NotificationCenter",
            swiftSettings: swift6
        )
    ]
)
