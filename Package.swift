// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpaceCrunch",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SpaceCrunch", targets: ["SpaceCrunch"]),
        .library(name: "SpaceCrunchCore", targets: ["SpaceCrunchCore"]),
    ],
    targets: [
        .target(
            name: "SpaceCrunchCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SpaceCrunch",
            dependencies: ["SpaceCrunchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SpaceCrunchCoreTests",
            dependencies: ["SpaceCrunchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
