// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "MemoryService",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MemoryService", targets: ["MemoryService"])
    ],
    targets: [
        .target(name: "MemoryService", swiftSettings: swift6),
        .testTarget(name: "MemoryServiceTests", dependencies: ["MemoryService"], swiftSettings: swift6)
    ]
)
