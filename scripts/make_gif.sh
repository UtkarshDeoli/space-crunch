#!/bin/bash
set -euo pipefail

# Assembles captured frames into a looping GIF.
#
# The frames come from the app's `--demo-dir` mode, which writes both the PNGs
# and a `durations.txt` manifest — one intended hold time per frame, in
# seconds. The manifest is what makes the pacing work: a screen the viewer
# should read lingers for a second and a half, while a frame that is only
# passing through during a scroll is held for a twentieth of one.
#
# Usage: scripts/make_gif.sh <frames-dir> <output.gif> [width]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FRAMES_DIR="${1:?usage: make_gif.sh <frames-dir> <output.gif> [width]}"
OUTPUT="${2:?usage: make_gif.sh <frames-dir> <output.gif> [width]}"
WIDTH="${3:-1000}"

if [[ ! -d "$FRAMES_DIR" ]]; then
  echo "error: $FRAMES_DIR is not a directory" >&2
  exit 1
fi

MANIFEST="$(dirname "$FRAMES_DIR")/durations.txt"
if [[ ! -f "$MANIFEST" ]]; then
  echo "error: $MANIFEST not found" >&2
  exit 1
fi

# Build an ffmpeg concat list. Each entry carries the frame's intended hold
# time, so ffmpeg holds that frame for exactly as long as the tour intended.
CONCAT="$(mktemp)"
trap 'rm -f "$CONCAT"' EXIT

count=0
while IFS= read -r duration; do
  frame="$(printf "%s/frames/%04d.png" "$(dirname "$FRAMES_DIR")" "$count")"
  if [[ ! -f "$frame" ]]; then
    echo "error: missing frame $frame" >&2
    exit 1
  fi
  printf "file '%s'\nduration %s\n" "$frame" "$duration" >> "$CONCAT"
  count=$((count + 1))
done < "$MANIFEST"

# The concat demuxer needs the last frame repeated, or it drops it.
last="$(printf "%s/frames/%04d.png" "$(dirname "$FRAMES_DIR")" "$((count - 1))")"
printf "file '%s'\n" "$last" >> "$CONCAT"

echo "==> Building $OUTPUT from $count frames"
mkdir -p "$(dirname "$OUTPUT")"

# Two passes: the first builds a palette from the frames, the second applies
# it. A single-pass GIF quantises per frame, which makes the colours flicker.
ffmpeg -y -loglevel error \
  -f concat -safe 0 -i "$CONCAT" \
  -vf "fps=40,scale=$WIDTH:--1:flags=lanczos,palettegen=stats_mode=diff" \
  -loop 0 "$OUTPUT"

ffmpeg -y -loglevel error \
  -f concat -safe 0 -i "$CONCAT" \
  -vf "fps=40,scale=$WIDTH:--1:flags=lanczos,paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 "$OUTPUT"

echo "==> Built $OUTPUT"
ls -lh "$OUTPUT"
