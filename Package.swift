// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypelessQuiet",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "TypelessQuietCore", targets: ["TypelessQuietCore"]),
        .executable(name: "TypelessQuiet", targets: ["TypelessQuietApp"]),
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
