// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoAI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "ShuoAI", targets: ["ShuoAI"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "ShuoAI",
            dependencies: ["ShuoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShuoAITests",
            dependencies: ["ShuoAI", "ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
