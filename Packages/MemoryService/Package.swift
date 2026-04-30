// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoryService",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MemoryService", targets: ["MemoryService"])
    ],
    targets: [
        .target(name: "MemoryService"),
        .testTarget(name: "MemoryServiceTests", dependencies: ["MemoryService"])
    ]
)
