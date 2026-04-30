// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeychainKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeychainKit", targets: ["KeychainKit"])
    ],
    targets: [
        .target(name: "KeychainKit"),
        .testTarget(name: "KeychainKitTests", dependencies: ["KeychainKit"])
    ]
)
