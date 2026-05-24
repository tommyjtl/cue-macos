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

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  MACOSX_DEPLOYMENT_TARGET=15.5 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=- \
  archive

APP_SRC="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
rm -rf "$APP_PATH"
cp -R "$APP_SRC" "$APP_PATH"

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

echo "Built unsigned release: $DMG_PATH"
