// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownstreamMarkdownHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SlopadEditor", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DownstreamMarkdownHost",
            dependencies: [
                .product(name: "SlopadEngine", package: "SlopadEditor"),
                .product(name: "SlopadEditorMarkdown", package: "SlopadEditor"),
            ]
        )
    ]
)
