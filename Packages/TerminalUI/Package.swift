// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "TerminalUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TerminalUI", targets: ["TerminalUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(path: "../SessionCore"),
        .package(path: "../AtomPalette")
    ],
    targets: [
        .target(name: "TerminalUI", dependencies: ["SwiftTerm", "SessionCore", "AtomPalette"], swiftSettings: swift6)
    ]
)
