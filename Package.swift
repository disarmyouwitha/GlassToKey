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
            url: "https://github.com/disarmyouwitha/GlassToKey/releases/download/v1.1.7/OpenMultitouchSupportXCF.xcframework.zip",
            checksum: "f01e2dc35bfcd65b5d817c1da2b2fd99da7d0ae0ec18da8d3f25cb211a37bb79"
        ),
        .target(
            name: "OpenMultitouchSupport",
            dependencies: ["OpenMultitouchSupportXCF"],
            swiftSettings: swiftSettings
        )
    ]
) 