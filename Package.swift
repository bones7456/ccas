// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CCAS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CCAS", targets: ["CCASApp"])
    ],
    targets: [
        .executableTarget(
            name: "CCASApp",
            path: "Sources/CCASApp"
        )
    ]
)
