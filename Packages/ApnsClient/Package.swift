// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ApnsClient",
    platforms: [.macOS("26.0")],
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
