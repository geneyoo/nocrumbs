// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "nocrumbs",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "nocrumbs",
            path: "Sources/nocrumbs"
        ),
    ]
)
