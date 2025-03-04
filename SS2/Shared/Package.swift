// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Shared",
            type: .dynamic,
            targets: ["Shared"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Shared",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ])
    ]
) 