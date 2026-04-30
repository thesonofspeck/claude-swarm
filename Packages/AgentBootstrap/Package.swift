// swift-tools-version: 6.0
import PackageDescription

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
            ]
        ),
        .testTarget(name: "AgentBootstrapTests", dependencies: ["AgentBootstrap"])
    ]
)
