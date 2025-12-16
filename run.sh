#!/bin/bash
# Run the screencap-cli tool with config.json

set -e

CONFIG_FILE="${1:-./config.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    echo "Usage: $0 [config-file]"
    exit 1
fi

echo "Running screencap-cli with config: $CONFIG_FILE"
exec .build/release/screencap-cli --config "$CONFIG_FILE"
