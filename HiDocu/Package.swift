// swift-tools-version: 5.9
// Package.swift for HiDocu macOS application
// This file enables SPM-based dependency management

import PackageDescription

let package = Package(
    name: "HiDocu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HiDocu",
            targets: ["HiDocu"]
        ),
    ],
    dependencies: [
        // Local JensenUSB package
        .package(path: "../JensenUSB"),
        // GRDB for SQLite
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
    ],
    targets: [
        .target(
            name: "HiDocu",
            dependencies: [
                "JensenUSB",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "HiDocu",
            exclude: ["Info.plist", "HiDocu.entitlements"],
            sources: [
                "App",
                "Core",
                "Data",
                "Domain",
                "Presentation",
            ]
        ),
        .testTarget(
            name: "HiDocuTests",
            dependencies: ["HiDocu"],
            path: "HiDocuTests"
        ),
    ]
)
