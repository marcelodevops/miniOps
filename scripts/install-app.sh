#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="miniOps"
DEFAULT_DEST="/Applications"
if [ ! -w "$DEFAULT_DEST" ]; then
    DEFAULT_DEST="$HOME/Applications"
    mkdir -p "$DEFAULT_DEST"
fi

DEST_DIR="$DEFAULT_DEST"
LAUNCH_AFTER=false
FORCE_BUILD=false
DO_ROLLBACK=false

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --dest <dir>   Installation directory (default: $DEFAULT_DEST)"
    echo "  -b, --build        Force rebuild before installing"
    echo "  -l, --launch       Launch miniOps after installation"
    echo "  -r, --rollback     Roll back to the previous backup (.app.bak)"
    echo "  -h, --help         Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dest)
            DEST_DIR="$2"
            shift 2
            ;;
        -b|--build)
            FORCE_BUILD=true
            shift
            ;;
        -l|--launch)
            LAUNCH_AFTER=true
            shift
            ;;
        -r|--rollback)
            DO_ROLLBACK=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

TARGET_APP="$DEST_DIR/${APP_NAME}.app"
BACKUP_APP="$DEST_DIR/${APP_NAME}.app.bak"

if [ "$DO_ROLLBACK" = true ]; then
    if [ ! -d "$BACKUP_APP" ]; then
        echo "Error: No previous backup found at $BACKUP_APP for rollback." >&2
        exit 1
    fi
    echo "==> Rolling back to previous build from $BACKUP_APP..."
    rm -rf "$TARGET_APP"
    cp -R "$BACKUP_APP" "$TARGET_APP"
    codesign --force --deep --sign - "$TARGET_APP"
    xattr -d com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    echo "==> Successfully rolled back ${APP_NAME} to $TARGET_APP"
    if [ "$LAUNCH_AFTER" = true ]; then
        echo "==> Launching rolled back $TARGET_APP..."
        open "$TARGET_APP"
    fi
    exit 0
fi

APP_SOURCE="$REPO_ROOT/.build/${APP_NAME}.app"

if [ "$FORCE_BUILD" = true ] || [ ! -d "$APP_SOURCE" ]; then
    echo "==> Building ${APP_NAME}..."
    "$REPO_ROOT/scripts/build-app.sh"
fi

echo "==> Installing ${APP_NAME}.app to $DEST_DIR..."
mkdir -p "$DEST_DIR"

if [ -d "$TARGET_APP" ]; then
    echo "    Backing up previous installation to $BACKUP_APP for safe rollback..."
    rm -rf "$BACKUP_APP"
    cp -R "$TARGET_APP" "$BACKUP_APP"
    rm -rf "$TARGET_APP"
fi

cp -R "$APP_SOURCE" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"

# Remove quarantine attribute if present
xattr -d com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "==> Successfully installed ${APP_NAME} to $TARGET_APP (previous build backed up to $BACKUP_APP)"

if [ "$LAUNCH_AFTER" = true ]; then
    echo "==> Launching $TARGET_APP..."
    open "$TARGET_APP"
fi
