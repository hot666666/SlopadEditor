// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownstreamArchiveHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "Slopad", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ArchiveCodecSurfaceProbe",
            dependencies: [
                .product(name: "SlopadArchive", package: "Slopad")
            ]
        ),
        .executableTarget(
            name: "AppKitArchiveLifecycleProbe",
            dependencies: [
                .product(name: "SlopadArchive", package: "Slopad"),
                .product(name: "SlopadAppKit", package: "Slopad"),
            ]
        ),
    ]
)
