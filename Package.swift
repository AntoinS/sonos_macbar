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
    dependencies: [
        .package(url: "https://github.com/CreatureSurvive/UPnPCast.git", exact: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "sonos_macbar",
            dependencies: [.product(name: "UPnPCast", package: "UPnPCast")],
            path: "Sources/sonos_macbar"
        ),
        .testTarget(
            name: "SonosMacbarTests",
            dependencies: ["sonos_macbar"]
        )
    ]
)
