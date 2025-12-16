# Claude Progress

## 2025-12-16 15:01 - Fixed Microphone Capture Not Working

**Problem**: Screen recording tool could capture system audio but not microphone audio on macOS 15.

**Root Cause**: ScreenCaptureKit's `captureMicrophone` feature requires an explicit `AVCaptureDevice.requestAccess(for: .audio)` call before enabling capture - having the permission in System Settings alone wasn't sufficient.

**Changes to `CaptureSession.swift`**:
1. Added `requestMicrophonePermission()` static method that explicitly requests microphone authorization via AVCaptureDevice API
2. Fixed `capturesAudio` logic - now only set `true` when system audio is actually requested (was incorrectly enabled for microphone-only config)
3. Added permission check before enabling `captureMicrophone` with clear error message if denied
4. Added separate tracking for system audio vs microphone samples for better diagnostics

**Result**: Microphone capture now works correctly. Test run captured 1244 microphone samples successfully.

## 2025-12-16 15:10 - Fixed Audio Format Conflict with Dual Audio Sources

**Problem**: Enabling both `system: true` and `microphone: true` caused AVAssetWriter to fail with error -12737 (format mismatch).

**Root Cause**: Both system audio and microphone samples were being written to a single `AVAssetWriterInput`. The two sources have different audio formats, causing the writer to fail when samples from both arrived.

**Fix**: Created separate audio inputs:
- `systemAudioInput` - receives `.audio` stream samples
- `microphoneInput` - receives `.microphone` stream samples

**Result**: Both audio sources can now be captured simultaneously. Output video contains two audio tracks (common for screen recordings - allows independent volume adjustment in post-production).

## 2025-12-16 18:55 - Swift 6 / macOS 15 Platform Investigation

**Goal**: Update to swift-tools-version 6.0 and `.macOS(.v15)` platform requirement.

**Attempts**:
1. Updated Package.swift to Swift 6.0 / macOS 15 - caused trace trap on Ctrl+C
2. Added `@unchecked Sendable` to CaptureSession - still crashed
3. Added serial isolation queue for thread-safe state access - still crashed
4. Added `-strict-concurrency=minimal` flag - still crashed
5. Reverted to Swift 5.10 with isolation queue changes - worked fine

**Conclusion**: The crash is in Swift 6's runtime itself, not our concurrency code. Signal handlers with DispatchSource appear incompatible with Swift 6's concurrency runtime. Staying on Swift 5.10 - the `#available` checks handle macOS 15 features at runtime anyway.

**Decision**: Discarded feature branch. Isolation queue adds complexity without benefit on Swift 5.10.
