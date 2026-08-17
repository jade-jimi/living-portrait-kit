// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LivingPortraitKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LivingPortraitCore", targets: ["LivingPortraitCore"]),
        .library(name: "LivingPortraitSwiftUI", targets: ["LivingPortraitSwiftUI"]),
    ],
    targets: [
        .target(
            name: "LivingPortraitCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "LivingPortraitSwiftUI",
            dependencies: ["LivingPortraitCore"]
        ),
        .testTarget(
            name: "LivingPortraitCoreTests",
            dependencies: ["LivingPortraitCore"]
        ),
    ]
)
