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

# Helper to build dependencies from source
build_source_deps() {
    echo "=== Building dependencies from source ==="
    
    if [ ! -e "third_party/ps5-elfldr/.git" ] || [ ! -e "third_party/ps5-kexp/.git" ] || [ ! -e "third_party/ps5-unified-autoloader/.git" ]; then
        echo "Error: Submodules are not initialized. Please run: git submodule update --init --recursive" >&2
        exit 1
    fi
    
    # Clean old binaries
    rm -f "$DEST_DIR"/elfldr-ps5-*.elf
    rm -f "$DEST_DIR"/kexp-*.bin
    rm -f "$DEST_DIR"/ps5-unified-autoloader*.elf
    
    echo "Building ps5-elfldr..."
    (cd third_party/ps5-elfldr && ./build.sh)
    ELFLDR_VER=$(git -C third_party/ps5-elfldr describe --tags --always)
    cp third_party/ps5-elfldr/elfldr-ps5.elf "$DEST_DIR/elfldr-ps5-${ELFLDR_VER}.elf"
    
    echo "Building ps5-kexp..."
    (cd third_party/ps5-kexp && ./build.sh)
    KEXP_VER=$(git -C third_party/ps5-kexp describe --tags --always)
    cp third_party/ps5-kexp/build/kexp.bin "$DEST_DIR/kexp-${KEXP_VER}.bin"
    
    echo "Building ps5-unified-autoloader..."
    (cd third_party/ps5-unified-autoloader && ./build_release.sh -b)
    AUTOLOADER_VER=$(git -C third_party/ps5-unified-autoloader describe --tags --always)
    AUTOLOADER_ELF=$(ls third_party/ps5-unified-autoloader/autoloader_v*.elf 2>/dev/null | head -n 1)
    if [ -z "$AUTOLOADER_ELF" ]; then
        echo "Error: ps5-unified-autoloader build succeeded but no output ELF found." >&2
        exit 1
    fi
    cp "$AUTOLOADER_ELF" "$DEST_DIR/ps5-unified-autoloader.elf"
    
    if [ "${GITHUB_OUTPUT:-}" ]; then
        echo "elfldr_ver=${ELFLDR_VER}" >> "$GITHUB_OUTPUT"
        echo "kexp_ver=${KEXP_VER}" >> "$GITHUB_OUTPUT"
        echo "unified_autoloader_ver=${AUTOLOADER_VER}" >> "$GITHUB_OUTPUT"
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
    HAS_AUTOLOADER=$(ls "$DEST_DIR"/ps5-unified-autoloader.elf 2>/dev/null | head -n 1)
    
    if [ -n "$HAS_KEXP" ] && [ -n "$HAS_ELFLDR" ] && [ -n "$HAS_AUTOLOADER" ]; then
        echo "Dependencies already present."
    else
        # If submodules checked out, build from source
        if [ -e "third_party/ps5-elfldr/.git" ] && [ -e "third_party/ps5-kexp/.git" ] && [ -e "third_party/ps5-unified-autoloader/.git" ]; then
            build_source_deps
        else
            download_prebuilt_deps
        fi
    fi
fi

echo "Creating LUA savedata update package..."
make all BUILD_TYPE=$BUILD_TYPE
