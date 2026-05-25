#!/usr/bin/env bash
set -e

# Ensure we are in the project root
cd "$(dirname "$0")"

BUILD_TYPE="dev"
DEP_ACTION="auto"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stable) BUILD_TYPE="stable" ;;
        --dev) BUILD_TYPE="dev" ;;
        --build-deps|-b) DEP_ACTION="build" ;;
        --download-deps|-d) DEP_ACTION="download" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

DEST_DIR="src"
AUTOLOADER_DIR="src/ps5_autoloader"

# Helper to generate autoload.txt
generate_autoload_txt() {
    local pldmgr_name="$1"
    mkdir -p "$AUTOLOADER_DIR"
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

$pldmgr_name
EOF
    echo "Generated $AUTOLOADER_DIR/autoload.txt pointing to $pldmgr_name"
}

# Helper to build dependencies from source
build_source_deps() {
    echo "=== Building dependencies from source ==="
    
    if [ ! -e "third_party/ps5-elfldr/.git" ] || [ ! -e "third_party/ps5-kexp/.git" ] || [ ! -e "third_party/ps5-payload-manager/.git" ]; then
        echo "Error: Submodules are not initialized. Please run: git submodule update --init --recursive" >&2
        exit 1
    fi
    
    # Clean old binaries
    rm -f "$DEST_DIR"/elfldr-ps5-*.elf
    rm -f "$DEST_DIR"/kexp-*.bin
    rm -f "$AUTOLOADER_DIR"/pldmgr-*.elf
    rm -f "$AUTOLOADER_DIR"/pldmgr_v*.elf
    rm -f "$AUTOLOADER_DIR"/autoload.txt
    
    echo "Building ps5-elfldr..."
    (cd third_party/ps5-elfldr && ./build.sh)
    ELFLDR_VER=$(git -C third_party/ps5-elfldr describe --tags --always)
    cp third_party/ps5-elfldr/elfldr-ps5.elf "$DEST_DIR/elfldr-ps5-${ELFLDR_VER}.elf"
    
    echo "Building ps5-kexp..."
    (cd third_party/ps5-kexp && ./build.sh)
    KEXP_VER=$(git -C third_party/ps5-kexp describe --tags --always)
    cp third_party/ps5-kexp/build/kexp.bin "$DEST_DIR/kexp-${KEXP_VER}.bin"
    
    echo "Building ps5-payload-manager..."
    (cd third_party/ps5-payload-manager && ./build_release.sh)
    PLDMGR_ELF=$(ls third_party/ps5-payload-manager/pldmgr_v*.elf 2>/dev/null | head -n 1)
    if [ -z "$PLDMGR_ELF" ]; then
        echo "Error: Failed to find built pldmgr ELF." >&2
        exit 1
    fi
    PLDMGR_NAME=$(basename "$PLDMGR_ELF")
    PLDMGR_VER=$(git -C third_party/ps5-payload-manager describe --tags --always)
    cp "$PLDMGR_ELF" "$AUTOLOADER_DIR/$PLDMGR_NAME"
    generate_autoload_txt "$PLDMGR_NAME"
    
    if [ "${GITHUB_OUTPUT:-}" ]; then
        echo "elfldr_ver=${ELFLDR_VER}" >> "$GITHUB_OUTPUT"
        echo "kexp_ver=${KEXP_VER}" >> "$GITHUB_OUTPUT"
        echo "pldmgr_ver=${PLDMGR_VER}" >> "$GITHUB_OUTPUT"
    fi
    
    echo "Source build complete."
}

# Helper to download dependencies
download_prebuilt_deps() {
    echo "=== Downloading dependencies from GitHub releases ==="
    ./scripts/download_deps.sh
}

# Resolve dependency action
if [ "$DEP_ACTION" = "download" ]; then
    download_prebuilt_deps
elif [ "$DEP_ACTION" = "build" ]; then
    build_source_deps
else
    # Auto mode: check if binaries exist
    HAS_KEXP=$(ls "$DEST_DIR"/kexp-*.bin 2>/dev/null | head -n 1)
    HAS_ELFLDR=$(ls "$DEST_DIR"/elfldr-ps5-*.elf 2>/dev/null | head -n 1)
    HAS_PLDMGR=$(ls "$AUTOLOADER_DIR"/pldmgr-*.elf "$AUTOLOADER_DIR"/pldmgr_v*.elf 2>/dev/null | head -n 1)
    
    if [ -n "$HAS_KEXP" ] && [ -n "$HAS_ELFLDR" ] && [ -n "$HAS_PLDMGR" ]; then
        echo "Dependencies already present."
        if [ ! -f "$AUTOLOADER_DIR/autoload.txt" ]; then
            PLDMGR_NAME=$(basename "$HAS_PLDMGR")
            generate_autoload_txt "$PLDMGR_NAME"
        fi
    else
        # If submodules checked out, build from source
        if [ -e "third_party/ps5-elfldr/.git" ] && [ -e "third_party/ps5-kexp/.git" ] && [ -e "third_party/ps5-payload-manager/.git" ]; then
            build_source_deps
        else
            download_prebuilt_deps
        fi
    fi
fi

echo "Creating LUA savedata update package..."
make all BUILD_TYPE=$BUILD_TYPE
