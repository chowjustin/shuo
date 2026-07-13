// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoAudio",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "ShuoAudio", targets: ["ShuoAudio"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "ShuoAudio",
            dependencies: ["ShuoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShuoAudioTests",
            dependencies: ["ShuoAudio", "ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
