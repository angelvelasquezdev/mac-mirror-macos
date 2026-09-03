// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMirror",
    platforms: [
        .macOS(.v14) // Support macOS Sonoma (14) and above
    ],
    products: [
        .executable(name: "MacMirror", targets: ["MacMirror"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacMirror",
            dependencies: [],
            path: "MacMirror",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "MacMirrorTests",
            dependencies: ["MacMirror"],
            path: "MacMirrorTests"
        )
    ]
)
