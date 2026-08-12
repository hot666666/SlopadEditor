// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SlopadEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SlopadEngine",
            targets: ["SlopadEngine"]
        ),
        .library(
            name: "SlopadMarkdown",
            targets: ["SlopadMarkdown"]
        ),
        .library(
            name: "SlopadEditorArchive",
            targets: ["SlopadEditorArchive"]
        ),
        .library(
            name: "SlopadAppKit",
            targets: ["SlopadAppKit"]
        ),
        .library(
            name: "SlopadEditorSwiftUI",
            targets: ["SlopadEditorSwiftUI"]
        ),
        .library(
            name: "SlopadAppKitTextKit",
            targets: ["SlopadAppKitTextKit"]
        ),
        .library(
            name: "SlopadAppKitUI",
            targets: ["SlopadAppKitUI"]
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
            name: "SlopadMarkdown",
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
            name: "SlopadEditorModel",
            dependencies: ["SlopadCoreModel", "SlopadEditorMarkdownInputRules"]
        ),
        .target(
            name: "SlopadBlockLayout",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
            ]
        ),
        .target(
            name: "SlopadEngine",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorModel",
                "SlopadBlockLayout",
            ]
        ),
        .target(
            name: "SlopadAppKitTextKit",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadAppKitUI",
            dependencies: [
                "SlopadEngine",
                "SlopadAppKitTextKit",
            ]
        ),
        .target(
            name: "SlopadAppKit",
            dependencies: [
                "SlopadEngine",
                "SlopadAppKitUI",
            ]
        ),
        // Layered on top of the AppKit facade rather than folded into it, for the same
        // reason SlopadAppKit is a curated umbrella and not a runtime owner.
        .target(
            name: "SlopadEditorSwiftUI",
            dependencies: ["SlopadAppKit"]
        ),
        .executableTarget(
            name: "SlopadHeightBenchmark",
            dependencies: [
                "SlopadCoreModel",
                "SlopadBlockLayout",
            ],
            path: "Benchmarks/SlopadHeightBenchmark"
        ),
        .executableTarget(
            name: "SlopadSessionBenchmark",
            dependencies: ["SlopadEngine"],
            path: "Benchmarks/SlopadSessionBenchmark"
        ),
        .executableTarget(
            name: "SlopadDebugApp",
            dependencies: [
                "SlopadEngine",
                "SlopadAppKitTextKit",
                "SlopadAppKitUI",
            ],
            path: "Debug/SlopadDebugApp"
        ),
        .executableTarget(
            name: "SlopadUIBenchmarkApp",
            dependencies: [
                "SlopadEngine",
                "SlopadAppKitTextKit",
                "SlopadAppKitUI",
            ],
            path: "Benchmarks/SlopadUIBenchmarkApp"
        ),
        .testTarget(
            name: "SlopadEngineTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
                "SlopadEditorModel",
                "SlopadBlockLayout",
                "SlopadEngine",
                "SlopadMarkdown",
                "SlopadEditorMarkdownInputRules",
            ]
        ),
        .testTarget(
            name: "SlopadMarkdownTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadMarkdown",
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
            name: "SlopadAppKitTextKitTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadAppKitTextKit",
            ]
        ),
        .testTarget(
            name: "SlopadAppKitUITests",
            dependencies: [
                "SlopadEngine",
                "SlopadAppKitUI",
            ]
        ),
        // SlopadAppKit is a test-only dependency: the tests construct a controller directly
        // to stand in for what `makeNSViewController` produces. SlopadEditorSwiftUI deliberately
        // does not re-export the controller, so a SwiftUI host cannot reach around it.
        .testTarget(
            name: "SlopadEditorSwiftUITests",
            dependencies: [
                "SlopadEditorSwiftUI",
                "SlopadAppKit",
            ]
        ),
    ]
)
