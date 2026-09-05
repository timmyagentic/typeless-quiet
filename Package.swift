// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypelessPlusPlus",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "TypelessPlusPlusCore", targets: ["TypelessQuietCore"]),
        .executable(name: "TypelessPlusPlus", targets: ["TypelessQuietApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "TypelessQuietCore"),
        .executableTarget(
            name: "TypelessQuietApp",
            dependencies: ["TypelessQuietCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(
            name: "TypelessQuietCoreTests",
            dependencies: ["TypelessQuietCore"]
        ),
        .testTarget(
            name: "TypelessQuietAppTests",
            dependencies: ["TypelessQuietApp", "TypelessQuietCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
