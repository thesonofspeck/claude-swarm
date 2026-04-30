// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GitKit", targets: ["GitKit"])
    ],
    targets: [
        .target(name: "GitKit"),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"])
    ]
)
