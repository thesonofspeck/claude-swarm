// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PairingProtocol",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "PairingProtocol", targets: ["PairingProtocol"])
    ],
    targets: [
        .target(name: "PairingProtocol"),
        .testTarget(name: "PairingProtocolTests", dependencies: ["PairingProtocol"])
    ]
)
