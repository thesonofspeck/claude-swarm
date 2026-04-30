// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnthropicClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnthropicClient", targets: ["AnthropicClient"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "AnthropicClient", dependencies: ["KeychainKit"]),
        .testTarget(name: "AnthropicClientTests", dependencies: ["AnthropicClient"])
    ]
)
