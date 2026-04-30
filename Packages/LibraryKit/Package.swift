// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LibraryKit", targets: ["LibraryKit"])
    ],
    dependencies: [
        .package(path: "../GitKit"),
        .package(path: "../AgentBootstrap")
    ],
    targets: [
        .target(name: "LibraryKit", dependencies: ["GitKit", "AgentBootstrap"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"])
    ]
)
