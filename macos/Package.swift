// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Strata", targets: ["Strata"])
    ],
    targets: [
        .target(name: "StrataCore"),
        .executableTarget(
            name: "Strata",
            dependencies: ["StrataCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Quartz"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .testTarget(
            name: "StrataCoreTests",
            dependencies: ["StrataCore"]
        ),
        .testTarget(
            name: "StrataTests",
            dependencies: ["Strata", "StrataCore"]
        ),
    ]
)
