#!/usr/bin/env bash
# Script to download dependency binaries from GitHub releases

set -euo pipefail

# Ensure we are in the project root
cd "$(dirname "$0")/.."

DEST_DIR="src"
mkdir -p "$DEST_DIR"

echo "Checking for curl..."
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required to download dependencies." >&2
    exit 1
fi

echo "Fetching latest release URL for ps5-elfldr..."
ELFLDR_URL=$(curl -s https://api.github.com/repos/itsPLK/ps5-elfldr/releases/latest | grep -o 'https://github.com/itsPLK/ps5-elfldr/releases/download/[^"]*\.elf' | head -n 1)
if [ -z "$ELFLDR_URL" ]; then
    echo "Error: Could not retrieve latest release URL for ps5-elfldr." >&2
    exit 1
fi

echo "Fetching latest release URL for ps5-kexp..."
KEXP_URL=$(curl -s https://api.github.com/repos/itsPLK/ps5-kexp/releases/latest | grep -o 'https://github.com/itsPLK/ps5-kexp/releases/download/[^"]*\.bin' | head -n 1)
if [ -z "$KEXP_URL" ]; then
    echo "Error: Could not retrieve latest release URL for ps5-kexp." >&2
    exit 1
fi

echo "Fetching latest release URL for ps5-unified-autoloader..."
AUTOLOADER_RELEASE_JSON=$(curl -s https://api.github.com/repos/itsPLK/ps5-unified-autoloader/releases/latest)
AUTOLOADER_URL=$(echo "$AUTOLOADER_RELEASE_JSON" | grep -o 'https://github.com/itsPLK/ps5-unified-autoloader/releases/download/[^"]*\.elf' | head -n 1)
if [ -z "$AUTOLOADER_URL" ]; then
    echo "Error: Could not retrieve latest release URL for ps5-unified-autoloader." >&2
    exit 1
fi

ELFLDR_VER=$(echo "$ELFLDR_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)
KEXP_VER=$(echo "$KEXP_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)
AUTOLOADER_VER=$(echo "$AUTOLOADER_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)

if [ "${GITHUB_OUTPUT:-}" ]; then
    echo "elfldr_ver=${ELFLDR_VER}" >> "$GITHUB_OUTPUT"
    echo "kexp_ver=${KEXP_VER}" >> "$GITHUB_OUTPUT"
    echo "unified_autoloader_ver=${AUTOLOADER_VER}" >> "$GITHUB_OUTPUT"
fi

# Clean old dependency files
echo "Cleaning old binaries from $DEST_DIR..."
rm -f "$DEST_DIR"/elfldr-ps5-*.elf
rm -f "$DEST_DIR"/kexp-*.bin
rm -f "$DEST_DIR"/ps5-unified-autoloader*.elf

ELFLDR_FILE="elfldr-ps5-${ELFLDR_VER}.elf"
KEXP_FILE="kexp-${KEXP_VER}.bin"
AUTOLOADER_FILE="ps5-unified-autoloader.elf"

# Download assets
echo "Downloading $ELFLDR_URL to $DEST_DIR/$ELFLDR_FILE..."
curl -L -o "$DEST_DIR/$ELFLDR_FILE" "$ELFLDR_URL"

echo "Downloading $KEXP_URL to $DEST_DIR/$KEXP_FILE..."
curl -L -o "$DEST_DIR/$KEXP_FILE" "$KEXP_URL"

echo "Downloading $AUTOLOADER_URL to $DEST_DIR/$AUTOLOADER_FILE..."
curl -L -o "$DEST_DIR/$AUTOLOADER_FILE" "$AUTOLOADER_URL"

echo "Successfully downloaded all dependencies!"
echo "Dependency versions:"
echo "  - elfldr: $ELFLDR_VER"
echo "  - kexp: $KEXP_VER"
echo "  - unified-autoloader: $AUTOLOADER_VER"
