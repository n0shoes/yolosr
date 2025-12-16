Most of the “design” work is done (framework choice, build setup, config schema, and a high‑level skeleton), but it still needs a few concrete pieces implemented before it will run end‑to‑end.[1][2]

## What is already covered

- Which Apple frameworks to use: `ScreenCaptureKit` for capture and `AVFoundation` for encoding/writing.[2][3][1]
- How to build without Xcode UI: SwiftPM executable target, `linkedFramework` entries, and `swift build -c release`.[4][5]
- Config schema + presets: source selection, resolution/fps, codec/bitrate, audio, MP4 vs MOV.[1][2]
- A skeleton for `main.swift`, config types, and a `CaptureSession` outline with `SCStream` + `AVAssetWriter`.[3][2][1]

## What’s left to implement

These are ideal hand‑offs to Claude Code:

- `PresetResolver.resolve(config:)` to merge `preset` and explicit `video.*` fields into final width/height/fps/bitrate/codec.[6][7]
- `resolveSource(from:)` to translate `source.type`/`id` into an `SCContentFilter` (primary display, specific window, or app).[3][1]
- A real stop mechanism (signal/keypress/duration) instead of the `asyncAfter` placeholder.[1]
- Optional: YAML parsing (swap JSONDecoder with a YAML lib) and some error/reporting polish.

So you have a solid spec and starting code; using Claude Code you can now “fill in the blanks” and iterate quickly on the concrete Swift implementation.

[1](https://developer.apple.com/documentation/screencapturekit/)
[2](https://developer.apple.com/documentation/avfoundation/avassetwriter)
[3](https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit)
[4](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/)
[5](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/)
[6](https://www.wowza.com/blog/what-is-video-bitrate-and-what-bitrate-should-you-use)
[7](https://macmost.com/creating-smaller-screen-capture-recordings-on-a-mac.html)