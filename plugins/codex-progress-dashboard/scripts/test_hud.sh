#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PLUGIN_ROOT=${SCRIPT_DIR:h}
SOURCE_DIR="$PLUGIN_ROOT/macos/Sources"
TEST_DIR="$PLUGIN_ROOT/macos/Tests"
BUILD_DIR="/tmp/codex-progress-dashboard-tests"
TEST_BINARY="$BUILD_DIR/HUDCoreTests"

mkdir -p "$BUILD_DIR"
clang \
  -O0 \
  -g \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path=/tmp/codex-progress-clang-modules \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  -I "$SOURCE_DIR" \
  "$TEST_DIR/HUDCoreTests.m" \
  "$SOURCE_DIR/DashboardModel.m" \
  "$SOURCE_DIR/HUDGeometry.m" \
  "$SOURCE_DIR/HUDInteractionController.m" \
  "$SOURCE_DIR/HUDIslandView.m" \
  "$SOURCE_DIR/HUDPresentationModel.m" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
