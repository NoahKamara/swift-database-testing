// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DatabaseTesting",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "DatabaseTesting",
            targets: ["DatabaseTesting"]
        ),
        .library(
            name: "DatabaseTestingCore",
            targets: ["DatabaseTestingCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftpackageindex/ShellOut", from: "3.3.0"),
    ],
    targets: [
        .target(
            name: "DatabaseTestingCore",
            dependencies: [
                .product(name: "ShellOut", package: "ShellOut"),
            ]
        ),
        .target(
            name: "DatabaseTesting",
            dependencies: [
                "DatabaseTestingCore",
            ]
        ),
        .testTarget(
            name: "DatabaseTestingTests",
            dependencies: [
                "DatabaseTestingCore",
                "DatabaseTesting",
                .product(name: "ShellOut", package: "ShellOut"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
