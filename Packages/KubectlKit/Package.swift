// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KubectlKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "KubectlKit", targets: ["KubectlKit"])
    ],
    targets: [
        .target(name: "KubectlKit"),
        .testTarget(name: "KubectlKitTests", dependencies: ["KubectlKit"])
    ]
)
