// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileBox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FileBox",
            path: "Sources/FileBox"
        ),
        .testTarget(
            name: "FileBoxTests",
            dependencies: ["FileBox"]
        )
    ]
)
