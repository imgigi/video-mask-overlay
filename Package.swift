// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VideoMaskOverlay",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VideoMaskOverlay"
        )
    ]
)
