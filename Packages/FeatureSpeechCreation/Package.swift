// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeatureSpeechCreation",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "FeatureSpeechCreation", targets: ["FeatureSpeechCreation"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
        .package(path: "../ShuoDesignSystem"),
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "FeatureSpeechCreation",
            dependencies: ["ShuoCore", "ShuoDesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureSpeechCreationTests",
            dependencies: ["FeatureSpeechCreation", "ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
