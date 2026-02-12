// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMService",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LLMService", targets: ["LLMService"])
    ],
    targets: [
        .target(name: "LLMService", path: "Sources/LLMService"),
        .testTarget(name: "LLMServiceTests", dependencies: ["LLMService"], path: "Tests/LLMServiceTests")
    ]
)
