// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WrikeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WrikeKit", targets: ["WrikeKit"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "WrikeKit", dependencies: ["KeychainKit"]),
        .testTarget(name: "WrikeKitTests", dependencies: ["WrikeKit"])
    ]
)
