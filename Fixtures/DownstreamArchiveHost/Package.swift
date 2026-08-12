// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownstreamArchiveHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SlopadEditor", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ArchiveCodecSurfaceProbe",
            dependencies: [
                .product(name: "SlopadArchive", package: "SlopadEditor")
            ]
        ),
        .executableTarget(
            name: "AppKitArchiveLifecycleProbe",
            dependencies: [
                .product(name: "SlopadArchive", package: "SlopadEditor"),
                .product(name: "SlopadAppKit", package: "SlopadEditor"),
            ]
        ),
    ]
)
