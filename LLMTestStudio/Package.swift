// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMTestStudio",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../LLMService")
    ],
    targets: [
        .executableTarget(
            name: "LLMTestStudio",
            dependencies: ["LLMService"],
            path: "Sources/LLMTestStudio"
        )
    ]
)
