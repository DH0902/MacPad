// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacPad",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, AppKit-free logic: file decoding, formatting, linting, diffing, search, tokenizing.
        .target(name: "MacPadCore"),
        // The AppKit app: windows, menus and panels on top of MacPadCore.
        .executableTarget(name: "MacPad", dependencies: ["MacPadCore"]),
        .testTarget(name: "MacPadCoreTests", dependencies: ["MacPadCore"]),
    ]
)
