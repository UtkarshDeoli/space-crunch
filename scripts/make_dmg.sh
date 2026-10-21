#!/bin/bash
set -euo pipefail

# Packages dist/SpaceCrunch.app into a compressed DMG with a symlink to
# /Applications, so dragging the app into place is one drag.
#
# Usage: scripts/make_dmg.sh [output-path]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="SpaceCrunch"
APP="$ROOT/dist/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found — run scripts/build_app.sh first" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
OUT="${1:-$ROOT/dist/$APP_NAME-$VERSION.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging $APP_NAME $VERSION"
# Copy the bundle itself, keeping the .app extension. Copying to an explicit
# destination name ("$STAGE/$APP_NAME") would drop the extension and produce
# a plain folder, which Finder won't launch.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A minimal .DS_Store keeps the volume tidy when opened in Finder.
touch "$STAGE/.DS_Store"

echo "==> Building $OUT"
rm -f "$OUT"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$OUT"

echo "==> Built $OUT"
ls -lh "$OUT"
