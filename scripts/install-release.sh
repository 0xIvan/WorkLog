#!/usr/bin/env bash
set -euo pipefail

REPO="${WORKLOG_REPO:-0xIvan/WorkLog}"
APP_NAME="Worklog"
INSTALL_DIR="${WORKLOG_INSTALL_DIR:-/Applications}"
ARCHIVE_URL="${WORKLOG_ARCHIVE_URL:-https://github.com/$REPO/releases/latest/download/$APP_NAME.app.zip}"
ARCHIVE_PATH="$APP_NAME.app.zip"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}

install_app() {
  if [[ -w "$INSTALL_DIR" ]]; then
    rm -rf "$TARGET_APP"
    ditto "$TEMP_DIR/$APP_NAME.app" "$TARGET_APP"
    return
  fi

  sudo rm -rf "$TARGET_APP"
  sudo ditto "$TEMP_DIR/$APP_NAME.app" "$TARGET_APP"
}

trap cleanup EXIT

echo "Downloading $ARCHIVE_URL"
curl --fail --location --progress-bar "$ARCHIVE_URL" --output "$TEMP_DIR/$ARCHIVE_PATH"

ditto -x -k "$TEMP_DIR/$ARCHIVE_PATH" "$TEMP_DIR"

if [[ ! -d "$TEMP_DIR/$APP_NAME.app" ]]; then
  echo "Could not find $APP_NAME.app in the downloaded archive." >&2
  exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
fi

install_app
open "$TARGET_APP"

echo "Installed $TARGET_APP"
