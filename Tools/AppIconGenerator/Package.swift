// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppIconGenerator",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "render-icon", targets: ["AppIconGenerator"])
    ],
    targets: [
        .executableTarget(name: "AppIconGenerator")
    ]
)
