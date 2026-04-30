// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersistenceKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PersistenceKit", targets: ["PersistenceKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "PersistenceKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "PersistenceKitTests", dependencies: ["PersistenceKit"])
    ]
)
