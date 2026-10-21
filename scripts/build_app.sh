#!/bin/bash
set -euo pipefail

# Builds a signed, double-clickable SpaceCrunch.app in dist/.
# Usage: scripts/build_app.sh [--open]
#
# Set SPACECRUNCH_VERSION to override the version baked into the bundle — the
# release workflow uses it to stamp the tag's version into the app.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="SpaceCrunch"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
BUNDLE_ID="com.utkarsh.spacecrunch"
VERSION="${SPACECRUNCH_VERSION:-1.0.0}"

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "error: release binary not found at $BIN" >&2
  exit 1
fi

echo "==> Generating app icon"
ICON_MASTER="$ROOT/assets/icon_1024.png"
swift "$ROOT/scripts/make_icon.swift" "$ICON_MASTER"

ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$ICON_MASTER" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ROOT/assets/AppIcon.icns"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>SpaceCrunch scans your Desktop to show what is using disk space.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>SpaceCrunch scans your Documents to show what is using disk space.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>SpaceCrunch scans your Downloads to find large files and old installers.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>SpaceCrunch scans removable volumes so you can see what is using space on them.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>SpaceCrunch scans network volumes so you can see what is using space on them.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signing is the default. Note that TCC keys its Full Disk Access grant
# to the code signature, and an ad-hoc signature changes with every build, so a
# rebuild can silently revoke the permission. Set SPACECRUNCH_SIGN_IDENTITY to a
# real development identity (for example an "Apple Development" certificate) to
# sign with something stable and keep the grant across rebuilds.
IDENTITY="${SPACECRUNCH_SIGN_IDENTITY:-}"
if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing with $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null
else
  echo "==> Signing (ad-hoc)"
  codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
fi

echo "==> Built $APP"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP"
fi
