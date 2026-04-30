// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitHubKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GitHubKit", targets: ["GitHubKit"])
    ],
    dependencies: [
        .package(path: "../GitKit")
    ],
    targets: [
        .target(name: "GitHubKit", dependencies: ["GitKit"]),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit"])
    ]
)
