// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SlopadEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SlopadEditorEngine",
            targets: ["SlopadEditorEngine"]
        ),
        .library(
            name: "SlopadEditorMarkdown",
            targets: ["SlopadEditorMarkdown"]
        ),
        .library(
            name: "SlopadEditorArchive",
            targets: ["SlopadEditorArchive"]
        ),
        .library(
            name: "SlopadEditorAppKit",
            targets: ["SlopadEditorAppKit"]
        ),
        .library(
            name: "SlopadEditorSwiftUI",
            targets: ["SlopadEditorSwiftUI"]
        ),
        .library(
            name: "SlopadEditorAppKitTextKit",
            targets: ["SlopadEditorAppKitTextKit"]
        ),
        .library(
            name: "SlopadEditorAppKitUI",
            targets: ["SlopadEditorAppKitUI"]
        ),
        .executable(
            name: "SlopadDebugApp",
            targets: ["SlopadDebugApp"]
        ),
        .executable(
            name: "SlopadUIBenchmarkApp",
            targets: ["SlopadUIBenchmarkApp"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.8.0"
        )
    ],
    targets: [
        .target(
            name: "SlopadCoreModel"
        ),
        // Markdown typed-input syntax is intentionally separate from the opt-in codec. It
        // contains only bounded pattern data and canonical rule effects — no parser target.
        .target(
            name: "SlopadEditorMarkdownInputRules",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorMarkdown",
            dependencies: [
                "SlopadCoreModel",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "SlopadEditorArchive",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorDataStructure"
        ),
        .target(
            name: "SlopadEditorDocumentModel",
            dependencies: ["SlopadCoreModel", "SlopadEditorMarkdownInputRules"]
        ),
        .target(
            name: "SlopadEditorBlockLayout",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
            ]
        ),
        .target(
            name: "SlopadEditorEngine",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDocumentModel",
                "SlopadEditorBlockLayout",
            ]
        ),
        .target(
            name: "SlopadEditorAppKitTextKit",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorAppKitUI",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitTextKit",
            ]
        ),
        .target(
            name: "SlopadEditorAppKit",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitUI",
            ]
        ),
        // Layered on top of the AppKit facade rather than folded into it, for the same
        // reason SlopadEditorAppKit is a curated umbrella and not a runtime owner.
        .target(
            name: "SlopadEditorSwiftUI",
            dependencies: ["SlopadEditorAppKit"]
        ),
        .executableTarget(
            name: "SlopadHeightBenchmark",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorBlockLayout",
            ],
            path: "Benchmarks/SlopadHeightBenchmark"
        ),
        .executableTarget(
            name: "SlopadSessionBenchmark",
            dependencies: ["SlopadEditorEngine"],
            path: "Benchmarks/SlopadSessionBenchmark"
        ),
        .executableTarget(
            name: "SlopadDebugApp",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Debug/SlopadDebugApp"
        ),
        .executableTarget(
            name: "SlopadUIBenchmarkApp",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Benchmarks/SlopadUIBenchmarkApp"
        ),
        .testTarget(
            name: "SlopadEditorEngineTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
                "SlopadEditorDocumentModel",
                "SlopadEditorBlockLayout",
                "SlopadEditorEngine",
                "SlopadEditorMarkdown",
                "SlopadEditorMarkdownInputRules",
            ]
        ),
        .testTarget(
            name: "SlopadEditorMarkdownTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorMarkdown",
            ]
        ),
        .testTarget(
            name: "SlopadEditorArchiveTests",
            dependencies: [
                "SlopadEditorArchive",
                "SlopadCoreModel",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SlopadEditorAppKitTextKitTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorAppKitTextKit",
            ]
        ),
        .testTarget(
            name: "SlopadEditorAppKitUITests",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitUI",
            ]
        ),
        // SlopadEditorAppKit is a test-only dependency: the tests construct a controller directly
        // to stand in for what `makeNSViewController` produces. SlopadEditorSwiftUI deliberately
        // does not re-export the controller, so a SwiftUI host cannot reach around it.
        .testTarget(
            name: "SlopadEditorSwiftUITests",
            dependencies: [
                "SlopadEditorSwiftUI",
                "SlopadEditorAppKit",
            ]
        ),
    ]
)
