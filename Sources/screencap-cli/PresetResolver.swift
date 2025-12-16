import Foundation
import AVFoundation

struct ResolvedVideoConfig {
    let width: Int
    let height: Int
    let fps: Int
    let codec: Any
    let bitrate: Int
}

enum PresetResolver {
    static func resolve(config: AppConfig) -> ResolvedVideoConfig {
        // Default preset values
        var width = 1920
        var height = 1080
        var fps = 30
        var bitrate = 4_000_000
        var codec: Any = AVVideoCodecType.h264

        // Apply preset if specified
        if let preset = config.preset {
            switch preset.lowercased() {
            case "low":
                width = 1280
                height = 720
                fps = 30
                bitrate = 2_000_000
            case "standard":
                width = 1920
                height = 1080
                fps = 30
                bitrate = 4_000_000
            case "high":
                width = 1920
                height = 1080
                fps = 60
                bitrate = 8_000_000
            default:
                break
            }
        }

        // Override with explicit video config values
        if let video = config.video {
            if let w = video.width { width = w }
            if let h = video.height { height = h }
            if let f = video.fps { fps = f }
            if let b = video.bitrate { bitrate = b }
            if let c = video.codec {
                switch c.lowercased() {
                case "h264":
                    codec = AVVideoCodecType.h264
                case "hevc":
                    codec = AVVideoCodecType.hevc
                default:
                    codec = AVVideoCodecType.h264
                }
            }
        }

        return ResolvedVideoConfig(
            width: width,
            height: height,
            fps: fps,
            codec: codec,
            bitrate: bitrate
        )
    }
}
