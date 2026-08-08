// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownstreamAppKitHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "Slopad", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DownstreamAppKitHost",
            dependencies: [
                .product(name: "SlopadAppKit", package: "Slopad")
            ]
        )
    ]
)
