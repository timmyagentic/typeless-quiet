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
    targets: [
        .target(name: "TypelessQuietCore"),
        .executableTarget(
            name: "TypelessQuietApp",
            dependencies: ["TypelessQuietCore"]
        ),
        .testTarget(
            name: "TypelessQuietCoreTests",
            dependencies: ["TypelessQuietCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
