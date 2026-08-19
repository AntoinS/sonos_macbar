// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "sonos_macbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "sonos_macbar",
            targets: ["sonos_macbar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "sonos_macbar",
            path: "Sources/sonos_macbar"
        )
    ]
)
