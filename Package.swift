// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacScreenRecorder",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "MacScreenRecorder", targets: ["MacScreenRecorder"])],
    targets: [
        .target(name: "RecorderCore"),
        .executableTarget(name: "MacScreenRecorder", dependencies: ["RecorderCore"]),
        .testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore"]),
    ]
)
