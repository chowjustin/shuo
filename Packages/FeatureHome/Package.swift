// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeatureHome",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "FeatureHome", targets: ["FeatureHome"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
        .package(path: "../ShuoDesignSystem"),
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "FeatureHome",
            dependencies: ["ShuoCore", "ShuoDesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureHomeTests",
            dependencies: ["FeatureHome", "ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
