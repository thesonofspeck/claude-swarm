// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "PairingProtocol",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "PairingProtocol", targets: ["PairingProtocol"])
    ],
    targets: [
        .target(name: "PairingProtocol", swiftSettings: swift6),
        .testTarget(name: "PairingProtocolTests", dependencies: ["PairingProtocol"], swiftSettings: swift6)
    ]
)
