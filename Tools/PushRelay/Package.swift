// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushRelay",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "swarm-push-relay", targets: ["swarm-push-relay"])
    ],
    dependencies: [
        .package(path: "../../Packages/ApnsClient"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "swarm-push-relay",
            dependencies: [
                "ApnsClient",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
