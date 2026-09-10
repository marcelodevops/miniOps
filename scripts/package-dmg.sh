#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="miniOps"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="$REPO_ROOT/dist"
OUTPUT_DMG="$DIST_DIR/$DMG_NAME"

echo "==> Step 1: Building release app bundle..."
"$REPO_ROOT/scripts/build-app.sh"

APP_PATH="$REPO_ROOT/.build/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at $APP_PATH" >&2
    exit 1
fi

echo "==> Step 2: Preparing DMG staging directory..."
STAGE_DIR="$(mktemp -d /tmp/miniOps-dmg-stage.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_PATH" "$STAGE_DIR/${APP_NAME}.app"
codesign --force --deep --sign - "$STAGE_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGE_DIR/Applications"

# Set volume icon if AppIcon.icns is available
if [ -f "$REPO_ROOT/Resources/AppIcon.icns" ]; then
    cp "$REPO_ROOT/Resources/AppIcon.icns" "$STAGE_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$STAGE_DIR/.VolumeIcon.icns" || true
        SetFile -a C "$STAGE_DIR" || true
    fi
fi

mkdir -p "$DIST_DIR"
rm -f "$OUTPUT_DMG"

echo "==> Step 3: Creating compressed disk image ($DMG_NAME)..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

# Also maintain a generic miniOps.dmg copy for convenience
cp "$OUTPUT_DMG" "$DIST_DIR/${APP_NAME}.dmg"

echo "==> DMG successfully created!"
echo "    Output: $OUTPUT_DMG"
echo "    Convenience alias: $DIST_DIR/${APP_NAME}.dmg"
ls -lh "$OUTPUT_DMG"
