// swift-tools-version: 6.0

import PackageDescription

// A downstream host that only exists to fail. It depends on the SlopadSwiftUI product the
// way a real app would — no `@testable`, no direct dependency on the underlying products,
// no access to package-only state — so anything a SwiftUI host needs that is not public
// breaks this build rather than being discovered by whoever integrates first.
let package = Package(
    name: "DownstreamSwiftUIHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DownstreamSwiftUIHost",
            dependencies: [
                .product(name: "SlopadSwiftUI", package: "Slopad")
            ]
        )
    ]
)
