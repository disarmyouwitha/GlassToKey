// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "OpenMultitouchSupport",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "OpenMultitouchSupport",
            targets: ["OpenMultitouchSupport"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "OpenMultitouchSupportXCF",
            // For development: use local framework
            // path: "OpenMultitouchSupportXCF.xcframework"
            // For release: use GitHub URL (replaced by release script)
            url: "https://github.com/disarmyouwitha/GlassToKey/releases/download/v1.1.4/OpenMultitouchSupportXCF.xcframework.zip",
            checksum: "fa3588ecd37b6e79d6837211bd3cc12687e34b755a08876da12fa2b1cd09a1d1"
        ),
        .target(
            name: "OpenMultitouchSupport",
            dependencies: ["OpenMultitouchSupportXCF"],
            swiftSettings: swiftSettings
        )
    ]
) 
