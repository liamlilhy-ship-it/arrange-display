// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayManager",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "DisplayManager",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/DisplayManager",
            linkerSettings: [
                // Sparkle.framework lives in the bundle's Contents/Frameworks;
                // swift build only bakes @loader_path, which resolves to MacOS/.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
