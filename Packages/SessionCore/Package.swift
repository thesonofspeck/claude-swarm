// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionCore", targets: ["SessionCore"])
    ],
    dependencies: [
        .package(path: "../PersistenceKit"),
        .package(path: "../GitKit")
    ],
    targets: [
        .target(name: "SessionCore", dependencies: ["PersistenceKit", "GitKit"]),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"])
    ]
)
