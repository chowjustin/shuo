// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeatureTranscriptAnalysis",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "FeatureTranscriptAnalysis", targets: ["FeatureTranscriptAnalysis"]),
    ],
    dependencies: [
        .package(path: "../ShuoCore"),
        .package(path: "../ShuoDesignSystem"),
        .package(path: "../ShuoTestSupport"),
    ],
    targets: [
        .target(
            name: "FeatureTranscriptAnalysis",
            dependencies: ["ShuoCore", "ShuoDesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureTranscriptAnalysisTests",
            dependencies: ["FeatureTranscriptAnalysis", "ShuoCore", "ShuoTestSupport"]
        ),
    ]
)
