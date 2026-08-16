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
        .library(name: "LivingPortraitAuthoring", targets: ["LivingPortraitAuthoring"]),
        .executable(name: "living-portrait-master", targets: ["LivingPortraitMasterCLI"]),
    ],
    targets: [
        .target(
            name: "LivingPortraitCore",
            resources: [.copy("Resources")]
        ),
        .target(
            name: "LivingPortraitSwiftUI",
            dependencies: ["LivingPortraitCore"]
        ),
        .target(
            name: "LivingPortraitAuthoring",
            dependencies: ["LivingPortraitCore"]
        ),
        .executableTarget(
            name: "LivingPortraitMasterCLI",
            dependencies: ["LivingPortraitAuthoring", "LivingPortraitCore"]
        ),
        .testTarget(
            name: "LivingPortraitCoreTests",
            dependencies: ["LivingPortraitCore"]
        ),
        .testTarget(
            name: "LivingPortraitAuthoringTests",
            dependencies: ["LivingPortraitAuthoring", "LivingPortraitCore"]
        ),
    ]
)
