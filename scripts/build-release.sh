#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/read-version.sh
source "$ROOT/scripts/read-version.sh"

DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Cue.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
APP_PATH="$EXPORT_DIR/Cue.app"
DMG_PATH="$DIST_DIR/Cue-${MARKETING_VERSION}.dmg"
SCHEME="Cue"
PROJECT="$ROOT/Cue.xcodeproj"

mkdir -p "$DIST_DIR" "$EXPORT_DIR"

SIGN_ARGS=()
if [[ "${RELEASE_SIGN:-0}" == "1" ]]; then
  : "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required when RELEASE_SIGN=1}"
  SIGN_ARGS+=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="Developer ID Application"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  )
  echo "Building signed release (team $DEVELOPMENT_TEAM)"
else
  SIGN_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGN_IDENTITY=-
  )
  echo "warning: building UNSIGNED release — permissions will not work on macOS 15+" >&2
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  MACOSX_DEPLOYMENT_TARGET=15.6 \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  "${SIGN_ARGS[@]}" \
  archive

APP_SRC="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
rm -rf "$APP_PATH"
cp -R "$APP_SRC" "$APP_PATH"

echo "Verifying app binary..."
lipo -info "$APP_PATH/Contents/MacOS/Cue"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Signature=' || true

if [[ "${RELEASE_SIGN:-0}" == "1" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  if ! codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -q 'TeamIdentifier='; then
    echo "error: app is not signed with a Developer ID team" >&2
    exit 1
  fi
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

rm -f "$DMG_PATH"
create-dmg \
  --volname "Cue ${MARKETING_VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "Cue.app" 150 185 \
  --hide-extension "Cue.app" \
  --app-drop-link 450 185 \
  "$DMG_PATH" \
  "$APP_PATH"

if [[ "${NOTARIZE_RELEASE:-0}" == "1" ]]; then
  : "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required for notarization}"
  : "${APPLE_ID:?APPLE_ID is required for notarization}"
  : "${APPLE_NOTARIZATION_PASSWORD:?APPLE_NOTARIZATION_PASSWORD is required for notarization}"

  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_NOTARIZATION_PASSWORD" \
    --team-id "$DEVELOPMENT_TEAM" \
    --wait

  xcrun stapler staple "$DMG_PATH"
  echo "Notarization complete"
fi

if [[ "${RELEASE_SIGN:-0}" == "1" ]]; then
  echo "Built signed release: $DMG_PATH"
else
  echo "Built unsigned release: $DMG_PATH"
fi
