#!/bin/bash
set -euo pipefail

# Captures every image asset the README uses: the still screenshots and the
# animated tour.
#
# The app scans the real home folder, so a full run takes a few minutes. The
# captures go through the window server, so the app has to be launched through
# LaunchServices (`open -a`) rather than run directly — a window that isn't key
# renders its accent-coloured controls in grey.
#
# Usage: scripts/capture_assets.sh [output-dir]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/docs}"
APP="$ROOT/dist/SpaceCrunch.app"

if [[ ! -d "$APP" ]]; then
  echo "==> Building the app"
  scripts/build_app.sh
fi

SCREENSHOTS="$OUT/screenshots"
GIF_DIR="$OUT/gifs"
mkdir -p "$SCREENSHOTS" "$GIF_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# MARK: - Still screenshots

capture_stills() {
  local appearance="$1"
  local dir="$WORK/stills-$appearance"

  echo "==> Capturing $appearance screenshots"
  rm -rf "$dir"
  mkdir -p "$dir"
  pkill -f "SpaceCrunch" 2>/dev/null || true
  sleep 1

  open -a "$APP" --args \
    --capture-dir "$dir" \
    --window-size 1280x800 \
    --appearance "$appearance"

  # The app terminates itself once the captures are written.
  local waited=0
  while pgrep -f "capture-dir $dir" >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [[ $waited -gt 1800 ]]; then
      echo "error: capture timed out" >&2
      pkill -f "capture-dir $dir" 2>/dev/null || true
      exit 1
    fi
  done

  for name in overview cleanup browse large-files; do
    local src="$dir/$appearance/$name.png"
    if [[ ! -f "$src" ]]; then
      echo "error: missing capture $src" >&2
      exit 1
    fi
    # Resize to a width GitHub renders well without a 2× download.
    sips --resampleHeightWidthMax 2000 "$src" \
      --out "$SCREENSHOTS/$name-$appearance.png" >/dev/null
    echo "    $SCREENSHOTS/$name-$appearance.png"
  done
}

# MARK: - Animated tour

capture_tour() {
  local dir="$WORK/tour"

  echo "==> Capturing the demo tour"
  rm -rf "$dir"
  mkdir -p "$dir"
  pkill -f "SpaceCrunch" 2>/dev/null || true
  sleep 1

  open -a "$APP" --args \
    --demo-dir "$dir" \
    --window-size 1280x800 \
    --appearance dark

  local waited=0
  while pgrep -f "demo-dir $dir" >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [[ $waited -gt 1800 ]]; then
      echo "error: demo capture timed out" >&2
      pkill -f "demo-dir $dir" 2>/dev/null || true
      exit 1
    fi
  done

  if [[ ! -f "$dir/durations.txt" ]]; then
    echo "error: the tour wrote no manifest — did the scan finish?" >&2
    exit 1
  fi

  echo "==> Building the GIF"
  scripts/make_gif.sh "$dir/frames" "$GIF_DIR/tour.gif" 1000
}

capture_stills dark
capture_stills light
capture_tour

echo "==> Done. Assets in $OUT"
ls -lh "$SCREENSHOTS" "$GIF_DIR"
