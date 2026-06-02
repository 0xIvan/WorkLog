#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Worklog"
APP_DIR="$ROOT_DIR/outputs/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION/$APP_NAME"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "$APP_DIR"
