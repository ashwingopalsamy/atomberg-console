// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ATOMBERG",
    // The `.v26` constant needs PackageDescription 6.2. The string form declares the same minimum under 6.0.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ATOMBERG",
            path: "Sources/ATOMBERG"
        ),
        .testTarget(
            name: "ATOMBERGTests",
            dependencies: ["ATOMBERG"],
            path: "Tests/ATOMBERGTests"
        ),
    ]
)
