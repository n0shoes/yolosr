# CLI UX Improvements - Nice to Have

## Overview
Improve the terminal output experience with better formatting, colors, and real-time status updates.

## Features

### 1. ANSI Color Output
Add color to terminal output for better readability:
- Green: Success messages (✓)
- Yellow: Warnings (⚠️)
- Red: Errors (❌)
- Cyan: Status/info messages
- Bold: Important values (file sizes, frame counts)

Consider a `--no-color` flag for piping/logging.

### 2. Single-Line Updating Status
Instead of printing a new line every second for file size, use terminal escape codes to update a single line in place:

```
Recording: 00:01:23 | 12.4 MB / 500 MB | Frames: 2,847
```

Use `\r` (carriage return) or ANSI escape `\033[2K` to clear/update the line.

### 3. Structured Startup Summary
Print a clean summary box on startup:

```
┌─────────────────────────────────────────┐
│ yolosr-swift Screen Recorder            │
├─────────────────────────────────────────┤
│ Source:    Display (Primary)            │
│ Resolution: 2560x1440 @ 30fps           │
│ Codec:     H.264 @ 24 Mbps              │
│ Audio:     System ✓  Mic ✓              │
│ Limit:     500 MB (warn at 75%)         │
│ Output:    ~/recordings/capture.mp4     │
└─────────────────────────────────────────┘
```

### 4. Recording Timer
Show elapsed time in HH:MM:SS format, updating in place.

### 5. Progress Bar for File Size
Visual progress toward the limit:

```
[████████░░░░░░░░░░░░] 42% (210 MB / 500 MB)
```

### 6. Final Summary
On completion, show a summary:

```
Recording Complete
──────────────────
Duration:    00:05:23
File Size:   234.5 MB
Frames:      9,690 video, 15,234 audio
Output:      /path/to/file.mp4
```

## Implementation Notes

### ANSI Escape Codes Reference
```swift
let red = "\u{001B}[31m"
let green = "\u{001B}[32m"
let yellow = "\u{001B}[33m"
let cyan = "\u{001B}[36m"
let bold = "\u{001B}[1m"
let reset = "\u{001B}[0m"

// Clear line and return cursor
let clearLine = "\u{001B}[2K\r"
```

### Detect TTY
Only use colors/updates if stdout is a terminal:
```swift
import Darwin
let isTTY = isatty(STDOUT_FILENO) != 0
```

### Update In Place
```swift
print("\r\u{001B}[2KRecording: \(elapsed) | \(size) MB", terminator: "")
fflush(stdout)
```

## Priority
Low - cosmetic improvements. Core functionality is complete.
