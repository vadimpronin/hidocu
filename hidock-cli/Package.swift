// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hidock-cli",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(path: "../JensenUSB"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "hidock-cli",
            dependencies: [
                .product(name: "JensenUSB", package: "JensenUSB"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources",
            exclude: ["make_prompt.sh"]
        ),
    ]
)
