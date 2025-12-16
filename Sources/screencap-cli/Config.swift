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

struct LimitsConfig: Decodable {
    let max_file_size_mb: Int?
    let warning_threshold_percent: Int?
}

struct NotificationsConfig: Decodable {
    let enable_notification: Bool?
    let warning_sound: String?
    let stop_sound: String?
}

struct AppConfig: Decodable {
    let source: SourceConfig
    let video: VideoConfig?
    let audio: AudioConfig?
    let output: OutputConfig
    let limits: LimitsConfig?
    let notifications: NotificationsConfig?
    let preset: String?
}

enum ConfigLoader {
    static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        // For YAML you'd plug in a YAML parser here; for now assume JSON.
        let decoder = JSONDecoder()
        let config = try decoder.decode(AppConfig.self, from: data)
        try config.validate()
        return config
    }
}

extension AppConfig {
    func validate() throws {
        // Validate source type
        let validSourceTypes = ["display", "window", "app"]
        guard validSourceTypes.contains(source.type.lowercased()) else {
            throw NSError(domain: "ConfigValidation", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid source type '\(source.type)'. Must be one of: \(validSourceTypes.joined(separator: ", "))"])
        }

        // Validate source ID is not empty
        guard !source.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "ConfigValidation", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Source ID cannot be empty"])
        }

        // Validate video config if present
        if let video = video {
            if let width = video.width, width <= 0 {
                throw NSError(domain: "ConfigValidation", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Video width must be positive, got \(width)"])
            }
            if let height = video.height, height <= 0 {
                throw NSError(domain: "ConfigValidation", code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "Video height must be positive, got \(height)"])
            }
            if let fps = video.fps, fps <= 0 || fps > 120 {
                throw NSError(domain: "ConfigValidation", code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "Video FPS must be between 1 and 120, got \(fps)"])
            }
            if let codec = video.codec {
                let validCodecs = ["h264", "hevc"]
                guard validCodecs.contains(codec.lowercased()) else {
                    throw NSError(domain: "ConfigValidation", code: 6,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid codec '\(codec)'. Must be one of: \(validCodecs.joined(separator: ", "))"])
                }
            }
            if let bitrate = video.bitrate, bitrate <= 0 {
                throw NSError(domain: "ConfigValidation", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "Video bitrate must be positive, got \(bitrate)"])
            }
        }

        // Validate audio config if present
        if let audio = audio {
            if let bitrate = audio.bitrate, bitrate <= 0 {
                throw NSError(domain: "ConfigValidation", code: 8,
                            userInfo: [NSLocalizedDescriptionKey: "Audio bitrate must be positive, got \(bitrate)"])
            }
        }

        // Validate output config
        guard !output.path.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "ConfigValidation", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "Output path cannot be empty"])
        }

        if let container = output.container {
            let validContainers = ["mp4", "mov"]
            guard validContainers.contains(container.lowercased()) else {
                throw NSError(domain: "ConfigValidation", code: 10,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid container '\(container)'. Must be one of: \(validContainers.joined(separator: ", "))"])
            }
        }

        // Validate preset if present
        if let preset = preset {
            let validPresets = ["low", "standard", "high"]
            guard validPresets.contains(preset.lowercased()) else {
                throw NSError(domain: "ConfigValidation", code: 11,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid preset '\(preset)'. Must be one of: \(validPresets.joined(separator: ", "))"])
            }
        }

        // Validate limits if present
        if let limits = limits {
            if let maxSize = limits.max_file_size_mb, maxSize <= 0 {
                throw NSError(domain: "ConfigValidation", code: 14,
                            userInfo: [NSLocalizedDescriptionKey: "Max file size must be positive, got \(maxSize)"])
            }
            if let threshold = limits.warning_threshold_percent, (threshold <= 0 || threshold > 100) {
                throw NSError(domain: "ConfigValidation", code: 15,
                            userInfo: [NSLocalizedDescriptionKey: "Warning threshold percent must be between 1 and 100, got \(threshold)"])
            }
        }

        // Validate notification sounds if present
        if let notifications = notifications {
            if let warningSound = notifications.warning_sound, !warningSound.isEmpty {
                guard FileManager.default.fileExists(atPath: warningSound) else {
                    throw NSError(domain: "ConfigValidation", code: 16,
                                userInfo: [NSLocalizedDescriptionKey: "Warning sound file not found: '\(warningSound)'"])
                }
            }
            if let stopSound = notifications.stop_sound, !stopSound.isEmpty {
                guard FileManager.default.fileExists(atPath: stopSound) else {
                    throw NSError(domain: "ConfigValidation", code: 17,
                                userInfo: [NSLocalizedDescriptionKey: "Stop sound file not found: '\(stopSound)'"])
                }
            }
        }

        // Validate output directory exists
        let expandedPath = NSString(string: output.path).expandingTildeInPath
        let outputURL = URL(fileURLWithPath: expandedPath)
        let outputDir = outputURL.deletingLastPathComponent()

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory) {
            throw NSError(domain: "ConfigValidation", code: 12,
                        userInfo: [NSLocalizedDescriptionKey: "Output directory does not exist: '\(outputDir.path)'. Please create it first."])
        } else if !isDirectory.boolValue {
            throw NSError(domain: "ConfigValidation", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Output directory path exists but is not a directory: '\(outputDir.path)'"])
        }
    }
}
