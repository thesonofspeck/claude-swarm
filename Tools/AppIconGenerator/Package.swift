// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "AppIconGenerator",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "render-icon", targets: ["AppIconGenerator"])
    ],
    targets: [
        .executableTarget(name: "AppIconGenerator", swiftSettings: swift6)
    ]
)
