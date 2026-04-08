// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TestDatabase",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "TestDatabase",
            targets: ["TestDatabase"]
        ),
        .library(
            name: "TestDatabaseTesting",
            targets: ["TestDatabaseTesting"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.32.2"),
        .package(url: "https://github.com/swiftpackageindex/ShellOut", from: "3.3.0"),
    ],
    targets: [
        .target(
            name: "TestDatabase",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ShellOut", package: "ShellOut"),
            ]
        ),
        .target(
            name: "TestDatabaseTesting",
            dependencies: [
                "TestDatabase",
            ]
        ),
        .testTarget(
            name: "TestDatabaseTests",
            dependencies: ["TestDatabase", "TestDatabaseTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
