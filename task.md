# YOLOSR-Swift Implementation Tasks

## Project Setup
- [x] Create Package.swift with proper platform and dependencies
- [x] Create Sources/screencap-cli directory structure
- [x] Create example config.yaml file
- [x] Create build.sh and run.sh scripts

## Core Implementation

### Config Layer
- [x] Implement Config.swift with all config structs (SourceConfig, VideoConfig, AudioConfig, OutputConfig, AppConfig)
- [x] Implement ConfigLoader.load(from:) with JSON support
- [ ] Optional: Add YAML parsing support

### Preset Resolution
- [x] Implement PresetResolver.resolve(config:) to merge presets with explicit config
- [x] Define preset constants (low, standard, high)
- [x] Handle override logic (explicit fields override preset)

### Capture Session - Core
- [x] Implement setupWriter() for AVAssetWriter configuration
- [x] Implement setupStream() for SCStream configuration
- [x] Implement awaitShareableContent() to fetch available sources
- [x] Implement resolveSource(from:) to map config.source to SCContentFilter
  - [x] Handle "primary" display
  - [x] Handle specific display by UUID
  - [x] Handle window by ID
  - [x] Handle app by bundle ID

### Capture Session - Stream Handling
- [x] Implement SCStreamDelegate conformance
- [x] Implement SCStreamOutput.stream(_:didOutputSampleBuffer:of:) for video
- [x] Implement audio sample buffer handling (if audio enabled)

### Lifecycle Management
- [x] Implement start(completion:) method
- [x] Implement stop(completion:) method with proper cleanup
- [x] Add signal handling (SIGINT/SIGTERM) for graceful shutdown
- [x] Replace 60-second timer with proper stop mechanism

### Main Entry Point
- [x] Implement main.swift argument parsing
- [x] Wire up config loading and CaptureSession initialization
- [x] Add error handling and user feedback

## Testing & Polish
- [ ] Test with display capture
- [ ] Test with window capture
- [ ] Test with app capture
- [ ] Test MP4 output (Windows compatibility)
- [ ] Test MOV output
- [ ] Test with audio enabled
- [ ] Test preset configurations (low, standard, high)
- [ ] Verify output file playback

## Documentation
- [ ] Add usage examples to README
- [ ] Document config options
- [ ] Add troubleshooting section
