// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DisplayManager",
            path: "Sources/DisplayManager"
        )
    ]
)
