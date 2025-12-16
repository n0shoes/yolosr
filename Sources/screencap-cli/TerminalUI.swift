import Foundation
import Darwin

/// Terminal UI utilities for colored output and status updates
final class TerminalUI {
    static let shared = TerminalUI()

    // ANSI escape codes
    private let red = "\u{001B}[31m"
    private let green = "\u{001B}[32m"
    private let yellow = "\u{001B}[33m"
    private let cyan = "\u{001B}[36m"
    private let bold = "\u{001B}[1m"
    private let reset = "\u{001B}[0m"
    private let clearLine = "\u{001B}[2K\r"

    /// Whether terminal colors are enabled
    var colorEnabled: Bool

    /// Whether stdout is a TTY (supports in-place updates)
    let isTTY: Bool

    /// Recording start time for elapsed time display
    private var recordingStartTime: Date?

    private init() {
        self.isTTY = isatty(STDOUT_FILENO) != 0
        self.colorEnabled = self.isTTY
    }

    // MARK: - Color Formatting

    func success(_ message: String) -> String {
        colorEnabled ? "\(green)\(message)\(reset)" : message
    }

    func warning(_ message: String) -> String {
        colorEnabled ? "\(yellow)\(message)\(reset)" : message
    }

    func error(_ message: String) -> String {
        colorEnabled ? "\(red)\(message)\(reset)" : message
    }

    func info(_ message: String) -> String {
        colorEnabled ? "\(cyan)\(message)\(reset)" : message
    }

    func boldText(_ message: String) -> String {
        colorEnabled ? "\(bold)\(message)\(reset)" : message
    }

    // MARK: - Status Symbols

    var checkmark: String { success("✓") }
    var warningSymbol: String { warning("⚠️") }
    var errorSymbol: String { error("❌") }
    var stopSymbol: String { error("🛑") }

    // MARK: - Startup Summary Box

    func printStartupSummary(
        sourceType: String,
        sourceId: String,
        resolution: String,
        fps: Int,
        codec: String,
        bitrate: Int,
        systemAudio: Bool,
        microphone: Bool,
        maxSizeMB: Int?,
        warningPercent: Int?,
        outputPath: String
    ) {
        let title = "yolosr-swift Screen Recorder"
        let boxWidth = 45
        let innerWidth = boxWidth - 4  // Account for "│ " and " │"

        func padRight(_ text: String, _ width: Int) -> String {
            let displayLen = stripAnsi(text).count
            if displayLen >= width {
                return String(text.prefix(width))
            }
            return text + String(repeating: " ", count: width - displayLen)
        }

        func formatLine(_ label: String, _ value: String) -> String {
            let formatted = "\(label.padding(toLength: 11, withPad: " ", startingAt: 0))\(value)"
            return "│ \(padRight(formatted, innerWidth)) │"
        }

        let bitrateStr = bitrate >= 1_000_000 ? "\(bitrate / 1_000_000) Mbps" : "\(bitrate / 1000) Kbps"

        let audioStatus: String
        let sysCheck = systemAudio ? checkmark : error("✗")
        let micCheck = microphone ? checkmark : error("✗")
        audioStatus = "System \(sysCheck)  Mic \(micCheck)"

        let limitStr: String
        if let maxSize = maxSizeMB {
            let warnPct = warningPercent ?? 75
            limitStr = "\(maxSize) MB (warn at \(warnPct)%)"
        } else {
            limitStr = "None"
        }

        let sourceDisplay = sourceId == "primary" ? "Display (Primary)" : "\(sourceType.capitalized) (\(sourceId))"

        print("┌\(String(repeating: "─", count: boxWidth - 2))┐")
        print("│ \(padRight(boldText(title), innerWidth)) │")
        print("├\(String(repeating: "─", count: boxWidth - 2))┤")
        print(formatLine("Source:", sourceDisplay))
        print(formatLine("Resolution:", "\(resolution) @ \(fps)fps"))
        print(formatLine("Codec:", "\(codec) @ \(bitrateStr)"))
        print(formatLine("Audio:", audioStatus))
        print(formatLine("Limit:", limitStr))
        print(formatLine("Output:", shortenPath(outputPath)))
        print("└\(String(repeating: "─", count: boxWidth - 2))┘")
    }

    // MARK: - Recording Status

    func startRecordingTimer() {
        recordingStartTime = Date()
    }

    func getElapsedTime() -> String {
        guard let startTime = recordingStartTime else { return "00:00:00" }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        if mb >= 1000 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    func progressBar(current: Int64, maxValue: Int64, width: Int = 20) -> String {
        let percent = maxValue > 0 ? Double(current) / Double(maxValue) : 0
        let filled = Int(percent * Double(width))
        let empty = width - filled

        let bar = String(repeating: "█", count: Swift.min(filled, width)) +
                  String(repeating: "░", count: Swift.max(empty, 0))

        let percentStr = String(format: "%3d%%", Int(percent * 100))
        return "[\(bar)] \(percentStr)"
    }

    func printRecordingStatus(elapsed: String, fileSizeBytes: Int64, maxSizeBytes: Int64?, frameCount: Int) {
        var status = info("Recording:") + " \(boldText(elapsed))"

        let sizeStr = formatBytes(fileSizeBytes)
        if let maxBytes = maxSizeBytes {
            let maxStr = formatBytes(maxBytes)
            status += " | \(sizeStr) / \(maxStr)"
            status += " | \(progressBar(current: fileSizeBytes, maxValue: maxBytes, width: 15))"
        } else {
            status += " | \(boldText(sizeStr))"
        }

        status += " | Frames: \(boldText(formatNumber(frameCount)))"

        if isTTY {
            print("\(clearLine)\(status)", terminator: "")
            fflush(stdout)
        } else {
            // For non-TTY, print on new lines periodically (handled by caller)
            print(status)
        }
    }

    func clearStatusLine() {
        if isTTY {
            print(clearLine, terminator: "")
            fflush(stdout)
        }
    }

    // MARK: - Final Summary

    func printFinalSummary(
        duration: String,
        fileSizeBytes: Int64,
        videoFrames: Int,
        systemAudioSamples: Int,
        microphoneSamples: Int,
        outputPath: String
    ) {
        // Move to new line after status updates
        print("")
        print("")

        print(boldText(success("Recording Complete")))
        print(String(repeating: "─", count: 20))
        print("Duration:    \(boldText(duration))")
        print("File Size:   \(boldText(formatBytes(fileSizeBytes)))")

        let audioStr: String
        if systemAudioSamples > 0 || microphoneSamples > 0 {
            audioStr = "\(formatNumber(videoFrames)) video, \(formatNumber(systemAudioSamples + microphoneSamples)) audio"
        } else {
            audioStr = "\(formatNumber(videoFrames)) video"
        }
        print("Frames:      \(audioStr)")

        if systemAudioSamples > 0 {
            print("             └─ System: \(formatNumber(systemAudioSamples))")
        }
        if microphoneSamples > 0 {
            print("             └─ Mic: \(formatNumber(microphoneSamples))")
        }

        print("Output:      \(outputPath)")
    }

    // MARK: - Helpers

    private func stripAnsi(_ text: String) -> String {
        // Remove ANSI escape sequences for accurate length calculation
        let pattern = "\u{001B}\\[[0-9;]*m"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func shortenPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        // If path is too long, show just the filename
        if path.count > 30 {
            return "..." + path.suffix(27)
        }
        return path
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
