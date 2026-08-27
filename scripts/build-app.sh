#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:a:h:h}
BUILD_DIR="$ROOT_DIR/.build/native"
APP_DIR="$BUILD_DIR/RuiTerm.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

# Prefer a complete Xcode toolchain when xcode-select points at the standalone
# CommandLineTools package, whose SwiftPM frameworks may be incomplete.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for developer_dir in \
    /Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode-beta.app/Contents/Developer
  do
    if [[ -d "$developer_dir/Toolchains/XcodeDefault.xctoolchain" ]]; then
      export DEVELOPER_DIR="$developer_dir"
      break
    fi
  done
fi

# SwiftPM builds all package dependencies, including CodeEditorView and
# LanguageSupport. Reusing that product avoids maintaining a second compiler
# invocation that can silently omit package modules.
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/RuiTerm" "$MACOS_DIR/RuiTerm"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/ruiterm-askpass.sh" "$RESOURCES_DIR/ruiterm-askpass.sh"
cp "$ROOT_DIR/Resources/RuiTerm.icns" "$RESOURCES_DIR/RuiTerm.icns"
chmod +x "$RESOURCES_DIR/ruiterm-askpass.sh"

for localization_dir in "$ROOT_DIR"/Resources/*.lproj; do
  if [[ -d "$localization_dir" ]]; then
    ditto "$localization_dir" "$RESOURCES_DIR/${localization_dir:t}"
  fi
done

if [[ -d "$BIN_DIR/RuiTerm_SwiftTerm.bundle" ]]; then
  ditto "$BIN_DIR/RuiTerm_SwiftTerm.bundle" "$RESOURCES_DIR/RuiTerm_SwiftTerm.bundle"
fi

if [[ -n "${RUITERM_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --sign "$RUITERM_SIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Resources/RuiTerm.entitlements" \
    "$APP_DIR"
  SIGNED_BUILD=true
else
  # Ad-hoc signatures cannot legally claim keychain-access-groups and macOS
  # kills such apps at launch. The app uses its LocalAuthentication fallback.
  codesign --force --deep --sign - "$APP_DIR"
  SIGNED_BUILD=false
fi

echo "$APP_DIR"

killall LightSSH 2>/dev/null || true
killall RuiTerm 2>/dev/null || true
sleep 0.5
if [[ "$SIGNED_BUILD" == true ]]; then
  open "$APP_DIR"
else
  # A brand-new ad-hoc app bundle identifier may be rejected by
  # AppleSystemPolicy. The raw SwiftPM product remains suitable for local
  # development; use a Developer ID identity to launch the packaged app.
  nohup "$BIN_DIR/RuiTerm" >/dev/null 2>&1 &!
fi
