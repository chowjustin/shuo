// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoTestSupport",
    // See ShuoCore/Package.swift — macOS is declared only to keep `swift test` working
    // on the host toolchain. ShuoTestSupport depends on ShuoCore alone.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ShuoTestSupport", targets: ["ShuoTestSupport"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
    ],
    targets: [
        .target(
            name: "ShuoTestSupport",
            dependencies: ["ShuoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
