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
    if [ ! -x "$BACKUP_APP/Contents/MacOS/$APP_NAME" ]; then
        echo "Error: Backup at $BACKUP_APP is corrupt (missing executable)." >&2
        exit 1
    fi

    echo "==> Staging and validating rollback from $BACKUP_APP..."
    STAGING_APP="$DEST_DIR/.${APP_NAME}.rollback.staging.$$"
    rm -rf "$STAGING_APP"
    cp -R "$BACKUP_APP" "$STAGING_APP"

    codesign --force --deep --sign - "$STAGING_APP"
    if ! codesign --verify --deep --strict "$STAGING_APP" 2>/dev/null; then
        echo "Error: Staged rollback failed code-signing verification. Aborting rollback without modifying installed app." >&2
        rm -rf "$STAGING_APP"
        exit 1
    fi

    echo "==> Swapping verified rollback into $TARGET_APP..."
    if [ -d "$TARGET_APP" ]; then
        TEMP_OLD="$DEST_DIR/.${APP_NAME}.prerollback.$$"
        mv "$TARGET_APP" "$TEMP_OLD"
        if mv "$STAGING_APP" "$TARGET_APP"; then
            rm -rf "$TEMP_OLD"
        else
            echo "Error: Failed to move staged rollback into place; restoring original installation." >&2
            mv "$TEMP_OLD" "$TARGET_APP"
            rm -rf "$STAGING_APP"
            exit 1
        fi
    else
        mv "$STAGING_APP" "$TARGET_APP"
    fi

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

if [ ! -x "$APP_SOURCE/Contents/MacOS/$APP_NAME" ]; then
    echo "Error: Built app source at $APP_SOURCE is invalid or missing executable." >&2
    exit 1
fi

echo "==> Installing ${APP_NAME}.app to $DEST_DIR..."
mkdir -p "$DEST_DIR"

# Stage and validate candidate app first before touching existing target or backup
STAGING_APP="$DEST_DIR/.${APP_NAME}.install.staging.$$"
rm -rf "$STAGING_APP"
cp -R "$APP_SOURCE" "$STAGING_APP"

codesign --force --deep --sign - "$STAGING_APP"
if ! codesign --verify --deep --strict "$STAGING_APP" 2>/dev/null; then
    echo "Error: Staged app failed code-signing verification. Aborting installation without touching existing install." >&2
    rm -rf "$STAGING_APP"
    exit 1
fi

# Stage backup of current installation if present
if [ -d "$TARGET_APP" ]; then
    echo "    Backing up previous installation to $BACKUP_APP for safe rollback..."
    BACKUP_STAGING="$DEST_DIR/.${APP_NAME}.backup.staging.$$"
    rm -rf "$BACKUP_STAGING"
    cp -R "$TARGET_APP" "$BACKUP_STAGING"
    rm -rf "$BACKUP_APP"
    mv "$BACKUP_STAGING" "$BACKUP_APP"

    TEMP_OLD="$DEST_DIR/.${APP_NAME}.old.$$"
    mv "$TARGET_APP" "$TEMP_OLD"
    if mv "$STAGING_APP" "$TARGET_APP"; then
        rm -rf "$TEMP_OLD"
    else
        echo "Error: Failed to swap staged app into place; restoring original installation." >&2
        mv "$TEMP_OLD" "$TARGET_APP"
        rm -rf "$STAGING_APP"
        exit 1
    fi
else
    mv "$STAGING_APP" "$TARGET_APP"
fi

# Remove quarantine attribute if present
xattr -d com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "==> Successfully installed ${APP_NAME} to $TARGET_APP (previous build backed up to $BACKUP_APP)"

if [ "$LAUNCH_AFTER" = true ]; then
    echo "==> Launching $TARGET_APP..."
    open "$TARGET_APP"
fi
