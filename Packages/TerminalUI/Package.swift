// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerminalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TerminalUI", targets: ["TerminalUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(path: "../SessionCore"),
        .package(path: "../AtomPalette")
    ],
    targets: [
        .target(name: "TerminalUI", dependencies: ["SwiftTerm", "SessionCore", "AtomPalette"]),
        .testTarget(name: "TerminalUITests", dependencies: ["TerminalUI"])
    ]
)
