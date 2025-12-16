Below is a single spec document you can drop into a repo as `SPEC.md` and use directly with Claude Code.

***

# macOS Screen Capture CLI – Spec

## Overview

A macOS‑only command‑line tool that:

- Captures screen (display/window/app) using **ScreenCaptureKit**.[1][2]
- Encodes video (and optional audio) to **H.264/HEVC** using **AVFoundation**, writing an **MP4** (Windows‑friendly) or MOV file.[3][4]
- Reads a simple **YAML/JSON config file** for capture and encoding settings.

No GUI, just `swift run` or a compiled binary plus a config file.

***

## Build Requirements

- macOS: latest (target at least macOS 14 in `Package.swift`).[1]
- Xcode **Command Line Tools** installed (for `swift`, `swiftc`, SDKs):  
  ```bash
  xcode-select --install
  ```


- Swift Package Manager (bundled with the tools).[5]

Directory layout (created by SwiftPM):

```text
screencap-cli/
  Package.swift
  Sources/
    screencap-cli/
      main.swift
      Config.swift        # config parsing / model
      CaptureSession.swift# SC + AVFoundation glue
  SPEC.md                # this file
  config.yaml            # example config
```

***

## Swift Package Configuration

`Package.swift`:

```swift
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
```

- `ScreenCaptureKit` is used for capture (`SCShareableContent`, `SCStream`).[2][1]
- `AVFoundation` for encoding/writing (`AVAssetWriter`, `AVAssetWriterInput`).[4][3]

Build and run:

```bash
swift build -c release
.build/release/screencap-cli --config ./config.yaml
```

***

## Config File Schema

Use YAML (or JSON with same keys). Example `config.yaml`:

```yaml
# capture source
source:
  type: display            # display | window | app
  id: primary              # "primary", display UUID, window ID, or bundle ID

# video format
video:
  width: 1920              # output width in pixels
  height: 1080             # output height in pixels
  fps: 30                  # frames per second
  codec: h264              # h264 | hevc
  bitrate: 4000000         # bits per second (e.g. 4 Mbps)

# audio (optional)
audio:
  system: true             # capture system audio if configured
  microphone: true         # capture default input
  bitrate: 128000          # AAC audio bitrate in bps

# output file
output:
  path: "/tmp/capture.mp4" # prefer MP4 for Windows compatibility
  container: mp4           # mp4 | mov

# preset for convenience (optional)
preset: standard           # low | standard | high
```

### Semantics and API Mapping

- `source.type` / `source.id`  
  - Use `SCShareableContent.current` to get displays/windows/apps.[2][1]
  - `display` + `id: primary` → first display.  
  - `window` → match by window ID.  
  - `app` → match by `bundleIdentifier`.  

- `video.width` / `video.height` / `video.fps`  
  - Map to `SCStreamConfiguration.width`, `.height`, `.minimumFrameInterval`.[1][2]

- `video.codec` / `video.bitrate`  
  - Map to `AVAssetWriterInput` `outputSettings` keys:  
    - `AVVideoCodecKey` (H.264/HEVC).[3][4]
    - `AVVideoWidthKey`, `AVVideoHeightKey`.  
    - `AVVideoCompressionPropertiesKey` → `AVVideoAverageBitRateKey`.[4][3]

- `audio.*`  
  - If enabled, create an audio `AVAssetWriterInput` with AAC settings (e.g. `kAudioFormatMPEG4AAC`, `AVEncoderBitRateKey`).[6][3]

- `output.container` / `output.path`  
  - `mp4` → `AVFileType.mp4` (recommended for Windows).[7][8]
  - `mov` → `AVFileType.mov`.  

- `preset` (sugar):  
  - `low` → 1280×720, 30 fps, 2 Mbps H.264.[9][10]
  - `standard` → 1920×1080, 30 fps, 4 Mbps H.264.[10][9]
  - `high` → 1920×1080, 60 fps, 8 Mbps H.264.  

Explicit `video.*` fields override preset defaults.

***

## Core Code Skeleton

### `main.swift`

Responsible for: argument parsing, loading config, starting capture.

```swift
import Foundation
import ScreenCaptureKit
import AVFoundation

@main
struct Main {
    static func main() throws {
        let args = CommandLine.arguments
        guard let configIndex = args.firstIndex(of: "--config"),
              args.count > configIndex + 1 else {
            fputs("Usage: screencap-cli --config /path/to/config.yaml\n", stderr)
            exit(1)
        }

        let configPath = args[configIndex + 1]
        let config = try ConfigLoader.load(from: URL(fileURLWithPath: configPath))

        let session = try CaptureSession(config: config)
        let group = DispatchGroup()
        group.enter()

        session.start {
            group.leave()
        }

        group.wait()
    }
}
```

### `Config.swift`

Define a minimal model and loader. Example for JSON (you can swap in YAML support easily).

```swift
import Foundation

struct SourceConfig: Decodable {
    let type: String   // "display" | "window" | "app"
    let id: String
}

struct VideoConfig: Decodable {
    let width: Int?
    let height: Int?
    let fps: Int?
    let codec: String?
    let bitrate: Int?
}

struct AudioConfig: Decodable {
    let system: Bool?
    let microphone: Bool?
    let bitrate: Int?
}

struct OutputConfig: Decodable {
    let path: String
    let container: String?
}

struct AppConfig: Decodable {
    let source: SourceConfig
    let video: VideoConfig?
    let audio: AudioConfig?
    let output: OutputConfig
    let preset: String?
}

enum ConfigLoader {
    static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        // For YAML you’d plug in a YAML parser here; for now assume JSON.
        let decoder = JSONDecoder()
        return try decoder.decode(AppConfig.self, from: data)
    }
}
```

### `CaptureSession.swift`

Pseudocode‑level skeleton that Claude can fill in more concretely:

```swift
import Foundation
import ScreenCaptureKit
import AVFoundation

final class CaptureSession: NSObject {
    private let config: AppConfig

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput?

    init(config: AppConfig) throws {
        self.config = config
        super.init()
        try setupWriter()
        try setupStream()
    }

    func start(completion: @escaping () -> Void) {
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)

        try? stream?.startCapture()

        // For now: simple signal to stop via stdin or duration.
        // Claude can wire a better stop mechanism (e.g. signal handlers).
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            self.stop(completion: completion)
        }
    }

    func stop(completion: @escaping () -> Void) {
        stream?.stopCapture { _ in
            self.videoInput.markAsFinished()
            self.audioInput?.markAsFinished()
            self.assetWriter.finishWriting {
                completion()
            }
        }
    }

    private func setupWriter() throws {
        let url = URL(fileURLWithPath: config.output.path)
        let fileType: AVFileType = (config.output.container == "mp4") ? .mp4 : .mov

        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)

        // Resolve preset + video config
        let resolved = PresetResolver.resolve(config: config)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: resolved.codec,
            AVVideoWidthKey: resolved.width,
            AVVideoHeightKey: resolved.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: resolved.bitrate
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        assetWriter.add(videoInput)

        if let audioCfg = config.audio, (audioCfg.system == true || audioCfg.microphone == true) {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: audioCfg.bitrate ?? 128_000,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                audioInput = input
            }
        }
    }

    private func setupStream() throws {
        let shareable = try awaitShareableContent()
        let source = try resolveSource(from: shareable)

        let configuration = SCStreamConfiguration()
        let resolved = PresetResolver.resolve(config: config)
        configuration.width = resolved.width
        configuration.height = resolved.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(resolved.fps))

        stream = SCStream(filter: source, configuration: configuration, delegate: self)
        try stream?.addStreamOutput(self,
                                   type: .screen,
                                   sampleHandlerQueue: .global())
        // Optional: add audio output as well.
    }

    private func awaitShareableContent() throws -> SCShareableContent {
        var result: Result<SCShareableContent, Error>!
        let sem = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let content = content {
                result = .success(content)
            } else {
                result = .failure(error ?? NSError(domain: "SC", code: -1))
            }
            sem.signal()
        }
        sem.wait()
        return try result.get()
    }

    private func resolveSource(from content: SCShareableContent) throws -> SCContentFilter {
        // Implement mapping of config.source → SCContentFilter using displays/windows/apps.
        // Claude can fill in e.g. primary display resolution matching.
        fatalError("unimplemented")
    }
}

extension CaptureSession: SCStreamDelegate {}

extension CaptureSession: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        switch outputType {
        case .screen:
            guard videoInput.isReadyForMoreMediaData else { return }
            videoInput.append(sampleBuffer)
        case .audio:
            guard let audioInput = audioInput,
                  audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        @unknown default:
            break
        }
    }
}
```

You can ask Claude Code to:

- Implement `PresetResolver.resolve(config:)`.  
- Implement `resolveSource(from:)` to respect `source.type` and `id`.  
- Add proper async/await instead of semaphores if desired.  

***

This spec gives the requirements, build setup, config schema, and core skeleton needed for Claude Code (or similar) to generate a working prototype of the CLI screen capture tool.

[1](https://developer.apple.com/documentation/screencapturekit/)
[2](https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit)
[3](https://developer.apple.com/documentation/avfoundation/avassetwriter)
[4](https://developer.apple.com/videos/play/wwdc2020/10010/)
[5](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/)
[6](https://stackoverflow.com/questions/48569738/swift-4-avfoundation-screen-and-audio-recording-using-avassetwriter-on-mac-os)
[7](https://support.microsoft.com/en-au/topic/file-types-supported-by-windows-media-player-32d9998e-dc8f-af54-7ba1-e996f74375d9)
[8](https://videoconvert.minitool.com/video-converter/mov-file-wont-play.html)
[9](https://www.wowza.com/blog/what-is-video-bitrate-and-what-bitrate-should-you-use)
[10](https://macmost.com/creating-smaller-screen-capture-recordings-on-a-mac.html)
[11](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/)
[12](https://stackoverflow.com/questions/9329243/how-to-install-xcode-command-line-tools)