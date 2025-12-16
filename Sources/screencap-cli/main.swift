import Foundation
import ScreenCaptureKit
import AVFoundation

let args = CommandLine.arguments
guard let configIndex = args.firstIndex(of: "--config"),
      args.count > configIndex + 1 else {
    fputs("Usage: screencap-cli --config /path/to/config.yaml\n", stderr)
    exit(1)
}

do {
    let configPath = args[configIndex + 1]
    let config = try ConfigLoader.load(from: URL(fileURLWithPath: configPath))

    let session = try CaptureSession(config: config)
    let group = DispatchGroup()
    group.enter()

    // Setup signal handlers for graceful shutdown on a background queue
    let signalQueue = DispatchQueue(label: "com.screencap.signals")
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)

    sigintSource.setEventHandler {
        print("\nReceived SIGINT, stopping capture...")
        session.stop {
            group.leave()
        }
        sigintSource.cancel()
        sigtermSource.cancel()
    }

    sigtermSource.setEventHandler {
        print("\nReceived SIGTERM, stopping capture...")
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
        // If start completes without signals, we shouldn't call leave
        // The signal handlers will call leave when triggered
    }

    group.wait()

    print("Recording stopped. Output saved to: \(session.outputURL.path)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
