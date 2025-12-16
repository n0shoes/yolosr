// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "screencap-cli",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "screencap-cli",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo")
            ]
        )
    ]
)
