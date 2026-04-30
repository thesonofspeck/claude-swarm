// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PairingService",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PairingService", targets: ["PairingService"])
    ],
    dependencies: [
        .package(path: "../PairingProtocol"),
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "PairingService", dependencies: ["PairingProtocol", "KeychainKit"]),
        .testTarget(name: "PairingServiceTests", dependencies: ["PairingService"])
    ]
)
