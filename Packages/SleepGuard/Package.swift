// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "SleepGuard",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SleepGuard", targets: ["SleepGuard"])
    ],
    targets: [
        .target(name: "SleepGuard", swiftSettings: swift6),
        .testTarget(name: "SleepGuardTests", dependencies: ["SleepGuard"], swiftSettings: swift6)
    ]
)
