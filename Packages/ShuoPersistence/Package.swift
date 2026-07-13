// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShuoPersistence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "ShuoPersistence", targets: ["ShuoPersistence"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
    ],
    targets: [
        .target(
            name: "ShuoPersistence",
            dependencies: ["ShuoCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShuoPersistenceTests",
            dependencies: ["ShuoPersistence", "ShuoCore"]
        ),
    ]
)
