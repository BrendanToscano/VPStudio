// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VPStudio",
    platforms: [
        .visionOS(.v2),
        .macOS(.v15),
    ],
    products: [
        .library(name: "VPStudio", targets: ["VPStudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/kingslay/KSPlayer", from: "2.2.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.0")),
    ],
    targets: [
        .target(
            name: "RealityKitContent",
            path: "Packages/RealityKitContent/Sources/RealityKitContent",
            resources: [.process("RealityKitContent.rkassets")]
        ),
        .target(
            name: "VPStudio",
            dependencies: [
                "RealityKitContent",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KSPlayer", package: "KSPlayer"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "VPStudio",
            exclude: [
                "Assets.xcassets",
                "App/VPStudioApp.swift",
                "Views/Windows/Player/PlayerView_Bug5_Fix.patch",
                "Views/Windows/Player/PlayerView_Bug5_Fix2.patch",
                "Views/Windows/Player/PlayerView_Bug5_Fix3.patch",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "VPStudioTests",
            dependencies: ["VPStudio"],
            path: "VPStudioTests"
        ),
    ]
)
