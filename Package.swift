// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screencap-cli",
    platforms: [
        .macOS(.v15)
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
