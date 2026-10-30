// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeQuest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeQuest", path: "Sources/ClaudeQuest")
    ]
)
