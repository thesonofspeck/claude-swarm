// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ApnsClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ApnsClient", targets: ["ApnsClient"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "ApnsClient", dependencies: ["KeychainKit"]),
        .testTarget(name: "ApnsClientTests", dependencies: ["ApnsClient"])
    ]
)
