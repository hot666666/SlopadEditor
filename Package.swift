// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Slopad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SlopadEngine",
            targets: ["SlopadEngine"]
        ),
        .library(
            name: "SlopadAppKit",
            targets: ["SlopadAppKit"]
        ),
        .library(
            name: "SlopadSwiftUI",
            targets: ["SlopadSwiftUI"]
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
        )
    ],
    targets: [
        .target(
            name: "SlopadCoreModel"
        ),
        .target(
            name: "SlopadDataStructure"
        ),
        .target(
            name: "SlopadEditorModel",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadBlockLayout",
            dependencies: [
                "SlopadCoreModel",
                "SlopadDataStructure",
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
            name: "SlopadSwiftUI",
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
                "SlopadDataStructure",
                "SlopadEditorModel",
                "SlopadBlockLayout",
                "SlopadEngine",
            ]
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
        // to stand in for what `makeNSViewController` produces. SlopadSwiftUI deliberately
        // does not re-export the controller, so a SwiftUI host cannot reach around it.
        .testTarget(
            name: "SlopadSwiftUITests",
            dependencies: [
                "SlopadSwiftUI",
                "SlopadAppKit",
            ]
        )
    ]
)
