#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:a:h:h}
BUILD_DIR="$ROOT_DIR/.build/native"
APP_DIR="$BUILD_DIR/RuiTerm.app"
DMG_NAME="RuiTerm.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"

if [[ ! -d "$APP_DIR" ]]; then
  echo "RuiTerm.app not found. Building app first..."
  "$ROOT_DIR/scripts/build-app.sh"
fi

echo "Packaging RuiTerm.app into $DMG_NAME..."

# Remove existing DMG if it exists
rm -f "$DMG_PATH"

# Create a staging directory
STAGING_DIR=$(mktemp -d)

# Copy the app to the staging directory
cp -R "$APP_DIR" "$STAGING_DIR/"

# Create a symlink to /Applications so users can drag-and-drop
ln -s /Applications "$STAGING_DIR/Applications"

# Create the DMG using hdiutil
hdiutil create -volname "RuiTerm" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# Clean up
rm -rf "$STAGING_DIR"

echo "✅ Successfully created DMG at: $DMG_PATH"
