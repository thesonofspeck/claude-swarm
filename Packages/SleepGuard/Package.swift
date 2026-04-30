// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepGuard",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SleepGuard", targets: ["SleepGuard"])
    ],
    targets: [
        .target(name: "SleepGuard"),
        .testTarget(name: "SleepGuardTests", dependencies: ["SleepGuard"])
    ]
)
