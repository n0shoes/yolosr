# yolosr-swift

A macOS command-line screen recording tool built with Swift and ScreenCaptureKit.

## Features

- Display, window, or app capture modes
- System audio capture
- Microphone capture (macOS 15+)
- H.264/HEVC video encoding
- Configurable via JSON or YAML
- File size limits with warning notifications
- Graceful shutdown with Ctrl+C

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Screen Recording permission (System Settings > Privacy & Security > Screen Recording)
- Microphone permission for mic capture (System Settings > Privacy & Security > Microphone)

## macOS Compatibility

| Feature | macOS 14 | macOS 15+ |
|---------|----------|-----------|
| Screen capture | ✓ | ✓ |
| System audio | ✓ | ✓ |
| Microphone | ✗ | ✓ |

Microphone capture via ScreenCaptureKit requires macOS 15 or later. On macOS 14, the tool will display a warning and continue without microphone capture. This is still useful for:

- Tutorials with app sounds only
- Gameplay recording
- Recording video calls (remote participant audio is system audio)
- Silent screen demos
- Music/media capture

## Installation

```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Build the project
./build.sh
```

The binary is built to `.build/release/screencap-cli`.

## Usage

```bash
# Create the output directory (must match the path in your config file)
mkdir -p ~/yolosr_recordings

# Run with the default config (config.json)
./run.sh

# Or specify a different config file
./run.sh /path/to/other-config.json
```

## Configuration

Create a JSON or YAML config file:

```json
{
  "source": {
    "type": "display",
    "id": "primary"
  },
  "video": {
    "width": 2560,
    "height": 1440,
    "fps": 30,
    "codec": "h264",
    "bitrate": 24000000
  },
  "audio": {
    "system": true,
    "microphone": true,
    "bitrate": 128000
  },
  "output": {
    "path": "~/yolosr_recordings/capture.mp4",
    "container": "mp4"
  },
  "preset": "standard"
}
```

### Source Types

- `display` - Capture a display (use `"id": "primary"` for main display)
- `window` - Capture a specific window by window ID
- `app` - Capture all windows of an app by bundle identifier

### Presets

- `low` - 1280x720, 30fps, 2 Mbps
- `standard` - 1920x1080, 30fps, 4 Mbps
- `high` - 1920x1080, 60fps, 8 Mbps

Explicit video settings override preset values.

### Audio

When both system audio and microphone are enabled, the output video contains two separate audio tracks. This allows independent volume adjustment in post-production.

## Permissions

On first run, macOS will prompt for Screen Recording permission. Grant access in System Settings > Privacy & Security > Screen Recording.

For microphone capture, also grant access in System Settings > Privacy & Security > Microphone.

## License

MIT
