// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentBootstrap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentBootstrap", targets: ["AgentBootstrap"])
    ],
    targets: [
        .target(
            name: "AgentBootstrap",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(name: "AgentBootstrapTests", dependencies: ["AgentBootstrap"])
    ]
)
