// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitKit", targets: ["GitKit"])
    ],
    targets: [
        .target(name: "GitKit"),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"])
    ]
)
