#!/usr/bin/env bash
# Script to download dependency binaries from GitHub releases

set -euo pipefail

# Ensure we are in the project root
cd "$(dirname "$0")/.."

DEST_DIR="src"
mkdir -p "$DEST_DIR"

AUTOLOADER_DIR="src/ps5_autoloader"
mkdir -p "$AUTOLOADER_DIR"

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

echo "Fetching latest release URL for ps5-payload-manager..."
PLDMGR_URL=$(curl -s https://api.github.com/repos/itsPLK/ps5-payload-manager/releases/latest | grep -o 'https://github.com/itsPLK/ps5-payload-manager/releases/download/[^"]*\.elf' | head -n 1)
if [ -z "$PLDMGR_URL" ]; then
    echo "Error: Could not retrieve latest release URL for ps5-payload-manager." >&2
    exit 1
fi
PLDMGR_FILE=$(basename "$PLDMGR_URL")

ELFLDR_VER=$(echo "$ELFLDR_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)
KEXP_VER=$(echo "$KEXP_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)
PLDMGR_VER=$(echo "$PLDMGR_URL" | grep -oE 'download/[^/]+' | cut -d'/' -f2)

if [ "${GITHUB_OUTPUT:-}" ]; then
    echo "elfldr_ver=${ELFLDR_VER}" >> "$GITHUB_OUTPUT"
    echo "kexp_ver=${KEXP_VER}" >> "$GITHUB_OUTPUT"
    echo "pldmgr_ver=${PLDMGR_VER}" >> "$GITHUB_OUTPUT"
fi

# Clean old dependency files
echo "Cleaning old binaries from $DEST_DIR..."
rm -f "$DEST_DIR"/elfldr-ps5-*.elf
rm -f "$DEST_DIR"/kexp-*.bin

echo "Cleaning old payload manager binaries from $AUTOLOADER_DIR..."
rm -f "$AUTOLOADER_DIR"/pldmgr-*.elf
rm -f "$AUTOLOADER_DIR"/pldmgr_v*.elf
rm -f "$AUTOLOADER_DIR"/autoload.txt

ELFLDR_FILE="elfldr-ps5-${ELFLDR_VER}.elf"
KEXP_FILE="kexp-${KEXP_VER}.bin"

# Download assets
echo "Downloading $ELFLDR_URL to $DEST_DIR/$ELFLDR_FILE..."
curl -L -o "$DEST_DIR/$ELFLDR_FILE" "$ELFLDR_URL"

echo "Downloading $KEXP_URL to $DEST_DIR/$KEXP_FILE..."
curl -L -o "$DEST_DIR/$KEXP_FILE" "$KEXP_URL"

echo "Downloading $PLDMGR_URL to $AUTOLOADER_DIR/$PLDMGR_FILE..."
curl -L -o "$AUTOLOADER_DIR/$PLDMGR_FILE" "$PLDMGR_URL"

echo "Generating autoload.txt with $PLDMGR_FILE..."
cat << EOF > "$AUTOLOADER_DIR/autoload.txt"
#
# ps5_autoloader
# autoload config file
# -----------------------------------------------------------------------------------------
# The loader looks for ps5_autoloader/autoload.txt in this order (highest priority first):
# 1) USB drives
# 2) /data directory
# 3) savedata directory
# Only the first autoload.txt found will be used.
#
# Usage:
# - Put one filename per line (e.g., payload.elf or script.lua).
# - Supported payload types: .elf, .bin, .lua
# - Lines starting with '!' are sleep commands (example: !1000 sleeps for 1000 ms).
#
# Notes:
# - The kernel exploit will start automatically - do NOT include it here!
# -----------------------------------------------------------------------------------------

$PLDMGR_FILE
EOF

echo "Successfully downloaded all dependencies!"
echo "Dependency versions:"
echo " - elfldr: $ELFLDR_VER"
echo " - kexp: $KEXP_VER"
echo " - pldmgr: $PLDMGR_VER"
