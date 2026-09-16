#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PLUGIN_ROOT=${SCRIPT_DIR:h}
SOURCE_DIR="$PLUGIN_ROOT/macos/Sources"
INFO_PLIST="$PLUGIN_ROOT/macos/Info.plist"
BUILD_DIR="$PLUGIN_ROOT/macos/build"
APP_DIR="$BUILD_DIR/CodexProgressHUD.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
clang \
  -O2 \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path=/tmp/codex-progress-clang-modules \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  -framework CoreGraphics \
  -framework QuartzCore \
  "$SOURCE_DIR"/*.m \
  -o "$MACOS_DIR/CodexProgressHUD"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
