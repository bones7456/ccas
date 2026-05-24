// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let infoPlistPath = "\(packageRoot)/Sources/CCASApp/Info.plist"

let package = Package(
    name: "CCAS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CCAS", targets: ["CCASApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CCASApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CCASApp",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlistPath])
            ]
        )
    ]
)
