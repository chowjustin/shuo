// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoCore",
    // iOS is the only shipping platform. macOS is declared solely so this package builds
    // for the host toolchain, keeping `swift test` usable as the fast inner loop
    // (CLAUDE.md §14) — ShuoCore is pure Foundation, so it costs nothing.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ShuoCore", targets: ["ShuoCore"]),
    ],
    dependencies: [
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "ShuoCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShuoCoreTests",
            dependencies: ["ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
