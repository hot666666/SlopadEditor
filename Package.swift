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
            name: "SlopadEditorDebugApp",
            targets: ["SlopadEditorDebugApp"]
        ),
        .executable(
            name: "SlopadEditorUIBenchmarkApp",
            targets: ["SlopadEditorUIBenchmarkApp"]
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
            name: "SlopadEditorCoreModel"
        ),
        // Markdown typed-input syntax is intentionally separate from the opt-in codec. It
        // contains only bounded pattern data and canonical rule effects — no parser target.
        .target(
            name: "SlopadEditorMarkdownInputRules",
            dependencies: ["SlopadEditorCoreModel"]
        ),
        .target(
            name: "SlopadEditorMarkdown",
            dependencies: [
                "SlopadEditorCoreModel",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "SlopadEditorArchive",
            dependencies: ["SlopadEditorCoreModel"]
        ),
        .target(
            name: "SlopadEditorDataStructure"
        ),
        .target(
            name: "SlopadEditorDocumentModel",
            dependencies: ["SlopadEditorCoreModel", "SlopadEditorMarkdownInputRules"]
        ),
        .target(
            name: "SlopadEditorBlockLayout",
            dependencies: [
                "SlopadEditorCoreModel",
                "SlopadEditorDataStructure",
            ]
        ),
        .target(
            name: "SlopadEditorEngine",
            dependencies: [
                "SlopadEditorCoreModel",
                "SlopadEditorDocumentModel",
                "SlopadEditorBlockLayout",
            ]
        ),
        .target(
            name: "SlopadEditorAppKitTextKit",
            dependencies: ["SlopadEditorCoreModel"]
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
            name: "SlopadEditorHeightBenchmark",
            dependencies: [
                "SlopadEditorCoreModel",
                "SlopadEditorBlockLayout",
            ],
            path: "Benchmarks/SlopadEditorHeightBenchmark"
        ),
        .executableTarget(
            name: "SlopadEditorSessionBenchmark",
            dependencies: ["SlopadEditorEngine"],
            path: "Benchmarks/SlopadEditorSessionBenchmark"
        ),
        .executableTarget(
            name: "SlopadEditorDebugApp",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Debug/SlopadEditorDebugApp"
        ),
        .executableTarget(
            name: "SlopadEditorUIBenchmarkApp",
            dependencies: [
                "SlopadEditorEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Benchmarks/SlopadEditorUIBenchmarkApp"
        ),
        .testTarget(
            name: "SlopadEditorEngineTests",
            dependencies: [
                "SlopadEditorCoreModel",
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
                "SlopadEditorCoreModel",
                "SlopadEditorMarkdown",
            ]
        ),
        .testTarget(
            name: "SlopadEditorArchiveTests",
            dependencies: [
                "SlopadEditorArchive",
                "SlopadEditorCoreModel",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SlopadEditorAppKitTextKitTests",
            dependencies: [
                "SlopadEditorCoreModel",
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
