#!/bin/bash
# Build the screencap-cli tool

set -e

echo "Building screencap-cli..."
swift build -c release

echo "✓ Build complete: .build/release/screencap-cli"
