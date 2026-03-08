// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RideOverlay",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "RideOverlayCore",
            targets: ["RideOverlayCore"]
        ),
    ],
    targets: [
        .target(
            name: "RideOverlayCore"
        ),
        .testTarget(
            name: "RideOverlayCoreTests",
            dependencies: ["RideOverlayCore"]
        ),
    ]
)
