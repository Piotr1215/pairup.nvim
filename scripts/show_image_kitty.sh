#!/usr/bin/env bash
# Display image using kitty graphics protocol (works in ghostty)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <image_path> [max_columns] [prompt_message] [--watch]"
    exit 1
fi

IMAGE_PATH="$1"
# Use 70% of terminal width to ensure height fits too
MAX_COLS="${2:-$(($(tput cols) * 7 / 10))}"
PROMPT="${3:-Press Enter to close...}"
WATCH_MODE="${4:-}"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image not found: $IMAGE_PATH"
    exit 1
fi

# Encode image to base64
IMAGE_DATA=$(base64 < "$IMAGE_PATH")

# Send kitty graphics protocol with aspect ratio preservation
# Use columns only (c), let height scale automatically
printf '\e_Gf=100,a=T,t=d,c=%d;%s\e\\' "$MAX_COLS" "$IMAGE_DATA"

# Wait for user input or sleep in watch mode
echo ""
if [ "$WATCH_MODE" = "--watch" ]; then
    # In watch mode, keep image visible until entr restarts
    sleep infinity
else
    read -p "$PROMPT"
fi
