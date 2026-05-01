// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "AgentBootstrap",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AgentBootstrap", targets: ["AgentBootstrap"])
    ],
    targets: [
        .target(
            name: "AgentBootstrap",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: swift6
        ),
        .testTarget(name: "AgentBootstrapTests", dependencies: ["AgentBootstrap"], swiftSettings: swift6)
    ]
)
