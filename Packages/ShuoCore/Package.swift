// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoCore",
    platforms: [.iOS(.v26)],
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
