import Foundation
import ScreenCaptureKit
import AVFoundation

let args = CommandLine.arguments

// Handle --no-color flag
if args.contains("--no-color") {
    TerminalUI.shared.colorEnabled = false
}

guard let configIndex = args.firstIndex(of: "--config"),
      args.count > configIndex + 1 else {
    fputs("Usage: screencap-cli --config /path/to/config.json [--no-color]\n", stderr)
    exit(1)
}

do {
    let configPath = args[configIndex + 1]
    let config = try ConfigLoader.load(from: URL(fileURLWithPath: configPath))
    let ui = TerminalUI.shared

    // Display startup summary
    let resolved = PresetResolver.resolve(config: config)
    let codecName: String
    if let codec = resolved.codec as? AVVideoCodecType {
        codecName = codec == .hevc ? "HEVC" : "H.264"
    } else {
        codecName = "H.264"
    }

    ui.printStartupSummary(
        sourceType: config.source.type,
        sourceId: config.source.id,
        resolution: "\(resolved.width)x\(resolved.height)",
        fps: resolved.fps,
        codec: codecName,
        bitrate: resolved.bitrate,
        systemAudio: config.audio?.system ?? false,
        microphone: config.audio?.microphone ?? false,
        maxSizeMB: config.limits?.max_file_size_mb,
        warningPercent: config.limits?.warning_threshold_percent,
        outputPath: config.output.path
    )
    print("")

    let session = try CaptureSession(config: config)
    let group = DispatchGroup()
    group.enter()

    // Setup signal handlers for graceful shutdown on a background queue
    let signalQueue = DispatchQueue(label: "com.screencap.signals")
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)

    sigintSource.setEventHandler {
        ui.clearStatusLine()
        print("\n\(ui.info("Received SIGINT, stopping capture..."))")
        session.stop {
            group.leave()
        }
        sigintSource.cancel()
        sigtermSource.cancel()
    }

    sigtermSource.setEventHandler {
        ui.clearStatusLine()
        print("\n\(ui.info("Received SIGTERM, stopping capture..."))")
        session.stop {
            group.leave()
        }
        sigintSource.cancel()
        sigtermSource.cancel()
    }

    // Ignore the default signal behavior
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    sigintSource.resume()
    sigtermSource.resume()

    session.start {
        // Called when recording ends (either by signal or auto-stop from file size limit)
        sigintSource.cancel()
        sigtermSource.cancel()
        group.leave()
    }

    group.wait()
} catch {
    let ui = TerminalUI.shared
    fputs("\(ui.error("Error:")) \(error)\n", stderr)
    exit(1)
}
