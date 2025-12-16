import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit
import CoreAudio

final class CaptureSession: NSObject {

    /// Request microphone permission and return authorization status
    static func requestMicrophonePermission() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var authorized = false

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            authorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                authorized = granted
                semaphore.signal()
            }
            semaphore.wait()
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }

        return authorized
    }
    private let config: AppConfig

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private(set) var outputURL: URL!

    private var fileSizeMonitorTimer: Timer?
    private var warningPlayed = false
    private var stopCompletion: (() -> Void)?
    private var frameCount = 0
    private var audioSampleCount = 0
    private var systemAudioSampleCount = 0
    private var microphoneSampleCount = 0
    private var firstFrameTime: CMTime?

    init(config: AppConfig) throws {
        self.config = config
        super.init()
        try setupWriter()
        try setupStream()
    }

    func start(completion: @escaping () -> Void) {
        guard assetWriter.status == .writing || assetWriter.status == .unknown else {
            print("Error: AVAssetWriter status is \(assetWriter.status.rawValue)")
            if let error = assetWriter.error {
                print("AVAssetWriter error: \(error.localizedDescription)")
            }
            return
        }

        assetWriter.startWriting()

        if assetWriter.status != .writing {
            print("⚠️  Warning: AVAssetWriter status is \(assetWriter.status.rawValue), expected .writing (1)")
        }

        stream?.startCapture()

        print("Recording started. Press Ctrl+C to stop...")
        print("Output: \(outputURL.path)")

        // Store completion for auto-stop
        stopCompletion = completion

        // Start file size monitoring if limits are configured
        if let limits = config.limits, let maxSize = limits.max_file_size_mb {
            startFileSizeMonitoring(maxSizeMB: maxSize,
                                  warningThresholdPercent: limits.warning_threshold_percent ?? 75)
        }
    }

    func stop(completion: @escaping () -> Void) {
        fileSizeMonitorTimer?.invalidate()
        fileSizeMonitorTimer = nil

        print("Stopping capture...")

        stream?.stopCapture { error in
            if let error = error {
                print("Error stopping capture: \(error.localizedDescription)")
            }

            print("Finalizing video file...")
            print("Captured \(self.frameCount) video frames, \(self.audioSampleCount) total audio samples")
            print("  - System audio samples: \(self.systemAudioSampleCount)")
            print("  - Microphone samples: \(self.microphoneSampleCount)")
            print("AVAssetWriter status before finish: \(self.assetWriter.status.rawValue)")

            if self.systemAudioSampleCount == 0 && self.systemAudioInput != nil {
                print("⚠️  No system audio samples - check if audio is playing during capture")
            }

            if self.microphoneSampleCount == 0 && self.microphoneInput != nil {
                print("⚠️  No microphone samples - verify microphone permission in System Settings")
            }

            guard self.assetWriter.status == .writing else {
                print("✗ Cannot finalize: AVAssetWriter is not in writing state")
                if let error = self.assetWriter.error {
                    print("Error: \(error.localizedDescription)")
                }
                completion()
                return
            }

            self.videoInput.markAsFinished()
            self.systemAudioInput?.markAsFinished()
            self.microphoneInput?.markAsFinished()

            self.assetWriter.finishWriting {
                print("AVAssetWriter status after finish: \(self.assetWriter.status.rawValue)")
                if self.assetWriter.status == .completed {
                    print("✓ Video file finalized successfully")
                } else if self.assetWriter.status == .failed {
                    print("✗ Video file finalization failed")
                    if let error = self.assetWriter.error {
                        print("Error: \(error.localizedDescription)")
                    }
                }
                completion()
            }
        }
    }

    private func startFileSizeMonitoring(maxSizeMB: Int, warningThresholdPercent: Int) {
        let maxSizeBytes = Int64(maxSizeMB) * 1024 * 1024
        let warningThresholdBytes = Int64(Double(maxSizeBytes) * Double(warningThresholdPercent) / 100.0)

        fileSizeMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: self.outputURL.path)
                if let fileSize = attributes[.size] as? Int64 {
                    let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0

                    // Check if warning threshold reached
                    if !self.warningPlayed && fileSize >= warningThresholdBytes {
                        self.warningPlayed = true
                        print("⚠️  Warning: File size reached \(warningThresholdPercent)% of limit (\(String(format: "%.1f", fileSizeMB)) MB)")
                        self.playWarningSound()
                    }

                    // Check if max size reached
                    if fileSize >= maxSizeBytes {
                        print("🛑 Maximum file size (\(maxSizeMB) MB) reached. Stopping recording...")
                        self.playStopSound()
                        self.fileSizeMonitorTimer?.invalidate()
                        self.fileSizeMonitorTimer = nil

                        if let completion = self.stopCompletion {
                            self.stop(completion: completion)
                        }
                    }
                }
            } catch {
                // File might not exist yet, ignore
            }
        }
    }

    private func playWarningSound() {
        guard let notifications = config.notifications,
              notifications.enable_notification == true,
              let soundPath = notifications.warning_sound else {
            return
        }

        if let sound = NSSound(contentsOfFile: soundPath, byReference: true) {
            sound.play()
        }
    }

    private func playStopSound() {
        guard let notifications = config.notifications,
              notifications.enable_notification == true,
              let soundPath = notifications.stop_sound else {
            return
        }

        if let sound = NSSound(contentsOfFile: soundPath, byReference: true) {
            sound.play()
            // Give sound time to play before stopping
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func setupWriter() throws {
        let expandedPath = NSString(string: config.output.path).expandingTildeInPath
        let url = timestampedURL(from: URL(fileURLWithPath: expandedPath))
        outputURL = url
        let fileType: AVFileType = (config.output.container == "mp4") ? .mp4 : .mov

        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)

        // Resolve preset + video config
        let resolved = PresetResolver.resolve(config: config)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: resolved.codec,
            AVVideoWidthKey: resolved.width,
            AVVideoHeightKey: resolved.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: resolved.bitrate,
                AVVideoExpectedSourceFrameRateKey: resolved.fps,
                AVVideoMaxKeyFrameIntervalKey: resolved.fps * 2
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        // Set transform for proper orientation
        videoInput.transform = CGAffineTransform(rotationAngle: 0)

        // Create pixel buffer adaptor with proper pixel format
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: resolved.width,
            kCVPixelBufferHeightKey as String: resolved.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        assetWriter.add(videoInput)

        // Create separate audio inputs for system audio and microphone
        // This allows both to be captured simultaneously without format conflicts
        if let audioCfg = config.audio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioCfg.bitrate ?? 128_000
            ]

            // System audio input
            if audioCfg.system == true {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                if assetWriter.canAdd(input) {
                    assetWriter.add(input)
                    systemAudioInput = input
                    print("✓ System audio input added to AVAssetWriter")
                } else {
                    print("⚠️  Failed to add system audio input to AVAssetWriter")
                }
            }

            // Microphone input (separate track)
            if audioCfg.microphone == true {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                if assetWriter.canAdd(input) {
                    assetWriter.add(input)
                    microphoneInput = input
                    print("✓ Microphone input added to AVAssetWriter")
                } else {
                    print("⚠️  Failed to add microphone input to AVAssetWriter")
                }
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

        // Configure audio BEFORE creating the stream
        if let audioCfg = config.audio, (audioCfg.system == true || audioCfg.microphone == true) {
            configuration.sampleRate = 48000
            configuration.channelCount = 2

            // Enable system audio capture only if requested
            if audioCfg.system == true {
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = false
                print("✓ System audio capture enabled")
            }

            // Enable microphone if requested (macOS 15+)
            if #available(macOS 15.0, *) {
                if audioCfg.microphone == true {
                    // Check microphone permission BEFORE enabling capture
                    let micAuthorized = CaptureSession.requestMicrophonePermission()
                    if micAuthorized {
                        configuration.captureMicrophone = true
                        print("✓ Microphone capture enabled")
                    } else {
                        print("⚠️  Microphone permission denied - check System Settings > Privacy & Security > Microphone")
                        print("   Grant microphone access to Terminal (or your app) and try again")
                    }
                }
            } else if audioCfg.microphone == true {
                print("⚠️  Microphone capture requires macOS 15+ (current: \(ProcessInfo.processInfo.operatingSystemVersionString))")
            }
        }

        stream = SCStream(filter: source, configuration: configuration, delegate: self)
        try stream?.addStreamOutput(self,
                                   type: .screen,
                                   sampleHandlerQueue: .global())

        // Add audio output if audio is configured
        if let audioCfg = config.audio, (audioCfg.system == true || audioCfg.microphone == true) {
            // Add system audio stream output
            if audioCfg.system == true {
                do {
                    try stream?.addStreamOutput(self,
                                               type: .audio,
                                               sampleHandlerQueue: .global())
                    print("✓ System audio stream output added")
                } catch {
                    print("⚠️  Failed to add system audio stream output: \(error)")
                }
            }

            // Add microphone stream output (macOS 15+)
            if #available(macOS 15.0, *) {
                if audioCfg.microphone == true {
                    do {
                        try stream?.addStreamOutput(self,
                                                   type: .microphone,
                                                   sampleHandlerQueue: .global())
                        print("✓ Microphone stream output added")
                    } catch {
                        print("⚠️  Failed to add microphone stream output: \(error)")
                    }
                }
            }
        }
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

    private func timestampedURL(from url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: Date())

        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        let timestampedFilename = "\(timestamp)_\(filename).\(ext)"
        return directory.appendingPathComponent(timestampedFilename)
    }

    private func resolveSource(from content: SCShareableContent) throws -> SCContentFilter {
        let sourceType = config.source.type.lowercased()
        let sourceId = config.source.id

        switch sourceType {
        case "display":
            // Handle display capture
            let display: SCDisplay
            if sourceId.lowercased() == "primary" {
                guard let primaryDisplay = content.displays.first else {
                    throw NSError(domain: "CaptureSession", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "No displays available"])
                }
                display = primaryDisplay
            } else {
                // Try to find display by UUID
                guard let foundDisplay = content.displays.first(where: {
                    String(describing: $0.displayID) == sourceId
                }) else {
                    throw NSError(domain: "CaptureSession", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Display with ID '\(sourceId)' not found"])
                }
                display = foundDisplay
            }
            return SCContentFilter(display: display, excludingWindows: [])

        case "window":
            // Handle window capture by window ID
            guard let windowID = UInt32(sourceId),
                  let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw NSError(domain: "CaptureSession", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Window with ID '\(sourceId)' not found"])
            }
            return SCContentFilter(desktopIndependentWindow: window)

        case "app":
            // Handle app capture by bundle identifier
            guard let app = content.applications.first(where: {
                $0.bundleIdentifier == sourceId
            }) else {
                throw NSError(domain: "CaptureSession", code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "Application with bundle ID '\(sourceId)' not found"])
            }
            // Get all windows for this app
            let appWindows = content.windows.filter { $0.owningApplication == app }
            if let display = content.displays.first {
                return SCContentFilter(display: display, including: appWindows)
            } else {
                throw NSError(domain: "CaptureSession", code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "No display available for app capture"])
            }

        default:
            throw NSError(domain: "CaptureSession", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown source type '\(sourceType)'. Use 'display', 'window', or 'app'"])
        }
    }
}

extension CaptureSession: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("\n❌ Stream stopped with error: \(error.localizedDescription)")
        print("\n⚠️  This is likely a permissions issue. Please:")
        print("1. Open System Settings > Privacy & Security > Screen Recording")
        print("2. Add Terminal (or your terminal app) to the allowed apps")
        print("3. Restart the terminal and try again")

        if let completion = stopCompletion {
            fileSizeMonitorTimer?.invalidate()
            completion()
        }
    }
}

extension CaptureSession: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        switch outputType {
        case .screen:
            guard videoInput.isReadyForMoreMediaData else {
                print("Warning: Video input not ready for more data")
                return
            }

            // Start the session with the first frame's timestamp
            if firstFrameTime == nil {
                firstFrameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                assetWriter.startSession(atSourceTime: firstFrameTime!)
                print("✓ Started AVAssetWriter session at time: \(firstFrameTime!.seconds)")
            }

            // Extract pixel buffer and append using adaptor
            // Some samples (like cursor updates) don't have image buffers, skip silently
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                frameCount += 1

                if frameCount == 1 {
                    print("✓ Receiving video frames")
                }
            } else {
                // Check for errors after appending
                if assetWriter.status == .failed {
                    if frameCount == 0 || frameCount % 100 == 0 {
                        print("❌ AVAssetWriter failed after frame \(frameCount)")
                        if let error = assetWriter.error {
                            print("Error: \(error)")
                        }
                    }
                }
            }
        case .audio:
            guard let systemAudioInput = systemAudioInput,
                  systemAudioInput.isReadyForMoreMediaData else { return }

            // Don't append audio until the writer session has started
            guard firstFrameTime != nil else {
                return
            }

            systemAudioInput.append(sampleBuffer)
            audioSampleCount += 1
            systemAudioSampleCount += 1

            if systemAudioSampleCount == 1 {
                print("✓ Receiving system audio samples")
            }

        case .microphone:
            guard let microphoneInput = microphoneInput,
                  microphoneInput.isReadyForMoreMediaData else { return }

            // Don't append audio until the writer session has started
            guard firstFrameTime != nil else {
                return
            }

            microphoneInput.append(sampleBuffer)
            audioSampleCount += 1
            microphoneSampleCount += 1

            if microphoneSampleCount == 1 {
                print("✓ Receiving microphone samples")

                // Debug: print audio format info (commented out for cleaner output)
                /*
                if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    if let streamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        print("   Audio format: \(streamBasicDesc.pointee.mFormatID)")
                        print("   Sample rate: \(streamBasicDesc.pointee.mSampleRate)")
                        print("   Channels: \(streamBasicDesc.pointee.mChannelsPerFrame)")
                        print("   Bits per channel: \(streamBasicDesc.pointee.mBitsPerChannel)")
                    }
                }

                // Check if audio buffer contains actual data
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    var length: Int = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    if CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr {
                        if let data = dataPointer {
                            let floats = data.withMemoryRebound(to: Float32.self, capacity: length / 4) { $0 }
                            var maxValue: Float32 = 0
                            for i in 0..<min(1000, length / 4) {
                                maxValue = max(maxValue, abs(floats[i]))
                            }
                            print("   Audio level (first samples): \(maxValue)")
                            if maxValue < 0.0001 {
                                print("   ⚠️  Audio appears to be silent - check microphone permissions!")
                            }
                        }
                    }
                }
                */
            }

            // Check for errors periodically
            if assetWriter.status == .failed && audioSampleCount % 100 == 0 {
                print("⚠️  AVAssetWriter failed during audio sample \(audioSampleCount)")
                if let error = assetWriter.error {
                    print("Error: \(error)")
                }
            }
        @unknown default:
            break
        }
    }
}
