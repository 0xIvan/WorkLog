#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Worklog"
APP_DIR="${1:-outputs/$APP_NAME.app}"
NOTARY_ARCHIVE="${2:-outputs/$APP_NAME-notarization.zip}"
SIGN_IDENTITY="${WORKLOG_CODE_SIGN_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

require_env() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "$name is required." >&2
    exit 1
  fi
}

require_env WORKLOG_CODE_SIGN_IDENTITY "$SIGN_IDENTITY"
require_env APPLE_ID "$APPLE_ID"
require_env APPLE_TEAM_ID "$APPLE_TEAM_ID"
require_env APPLE_APP_SPECIFIC_PASSWORD "$APPLE_APP_SPECIFIC_PASSWORD"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Could not find app bundle at $APP_DIR." >&2
  exit 1
fi

codesign \
  --force \
  --deep \
  --timestamp \
  --options runtime \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$NOTARY_ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ARCHIVE"

xcrun notarytool submit "$NOTARY_ARCHIVE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR"
