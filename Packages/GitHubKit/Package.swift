// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitHubKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitHubKit", targets: ["GitHubKit"])
    ],
    dependencies: [
        .package(path: "../KeychainKit")
    ],
    targets: [
        .target(name: "GitHubKit", dependencies: ["KeychainKit"]),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit"])
    ]
)
