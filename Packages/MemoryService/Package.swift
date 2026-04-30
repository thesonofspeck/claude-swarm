// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoryService",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MemoryService", targets: ["MemoryService"]),
        .executable(name: "swarm-memory-mcp", targets: ["SwarmMemoryMCP"])
    ],
    dependencies: [
        .package(path: "../PersistenceKit")
    ],
    targets: [
        .target(name: "MemoryService", dependencies: ["PersistenceKit"]),
        .executableTarget(
            name: "SwarmMemoryMCP",
            dependencies: ["MemoryService"]
        ),
        .testTarget(name: "MemoryServiceTests", dependencies: ["MemoryService"])
    ]
)
