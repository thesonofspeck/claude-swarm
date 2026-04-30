// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PairingProtocol",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PairingProtocol", targets: ["PairingProtocol"])
    ],
    targets: [
        .target(name: "PairingProtocol"),
        .testTarget(name: "PairingProtocolTests", dependencies: ["PairingProtocol"])
    ]
)
