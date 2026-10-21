#!/bin/bash
set -euo pipefail

# Assembles captured frames into a looping GIF.
#
# The frames come from the app's `--demo-dir` mode, which writes both the PNGs
# and a `durations.txt` manifest — one line per frame, holding how long to show
# it and whether it was captured mid-scroll. The manifest is what makes the
# pacing work: a screen the viewer should read lingers for a second and a half,
# while a frame that is only passing through during a scroll is held for a
# twentieth of one.
#
# Usage: scripts/make_gif.sh <frames-dir> <output.gif> [width] [palette-colours]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FRAMES_DIR="${1:?usage: make_gif.sh <frames-dir> <output.gif> [width] [palette-colours]}"
OUTPUT="${2:?usage: make_gif.sh <frames-dir> <output.gif> [width] [palette-colours]}"
WIDTH="${3:-900}"
COLORS="${4:-128}"

# How many frames to keep from each scroll. A scroll needs enough to read as
# movement, but one frame per scroll step triples the file for no gain — and
# the dwell frame after the scroll is what the viewer actually reads.
MOTION_FRAMES=3

if [[ ! -d "$FRAMES_DIR" ]]; then
  echo "error: $FRAMES_DIR is not a directory" >&2
  exit 1
fi

MANIFEST="$(dirname "$FRAMES_DIR")/durations.txt"
if [[ ! -f "$MANIFEST" ]]; then
  echo "error: $MANIFEST not found" >&2
  exit 1
fi

# Build an ffmpeg concat list. Each entry carries the frame's hold time, so
# ffmpeg holds that frame for exactly as long as the tour intended.
CONCAT="$(mktemp)"
SEL="$(mktemp)"
trap 'rm -f "$CONCAT" "$SEL"' EXIT

# The manifest is "seconds motion" per line. Frames are thinned per scroll:
# a run of consecutive motion frames is reduced to MOTION_FRAMES evenly-spaced
# frames, and the hold times of the dropped frames are folded into the
# survivors so the scroll still takes the same wall-clock time.
#
# The thinning is done in awk rather than in the shell because the run
# boundaries have to be known before any frame can be dropped.
awk -v keep="$MOTION_FRAMES" '
  { seconds[NR] = $1; motion[NR] = ($2 == 1) }

  # Emit one kept frame: its zero-based index and the hold time it stands for.
  function emit(i, hold) { printf "%d %.4f\n", i, hold }

  END {
    n = 1
    while (n <= NR) {
      if (!motion[n]) {
        # A dwell frame is a screen the viewer reads. Always keep it.
        emit(n - 1, seconds[n])
        n++
        continue
      }
      # A run of motion frames: one scroll.
      start = n
      while (n <= NR && motion[n]) n++
      end = n - 1
      run = end - start + 1
      if (run <= keep) {
        for (j = start; j <= end; j++) emit(j - 1, seconds[j])
      } else {
        total = 0
        for (j = start; j <= end; j++) total += seconds[j]
        for (k = 0; k < keep; k++) {
          offset = int(k * (run - 1) / (keep - 1) + 0.5)
          emit(start + offset - 1, total / keep)
        }
      }
    }
  }
' "$MANIFEST" > "$SEL"

count=0
while read -r index hold; do
  frame="$(printf "%s/%04d.png" "$FRAMES_DIR" "$index")"
  if [[ ! -f "$frame" ]]; then
    echo "error: missing frame $frame" >&2
    exit 1
  fi
  printf "file '%s'\nduration %s\n" "$frame" "$hold" >> "$CONCAT"
  count=$((count + 1))
done < "$SEL"

if [[ $count -eq 0 ]]; then
  echo "error: $MANIFEST listed no frames" >&2
  exit 1
fi

# The concat demuxer needs the last frame repeated, or it drops it.
last_index="$(awk 'END { print $1 }' "$SEL")"
printf "file '%s/%04d.png'\n" "$FRAMES_DIR" "$last_index" >> "$CONCAT"

echo "==> Building $OUTPUT from $count frames"
mkdir -p "$(dirname "$OUTPUT")"

PALETTE="$(mktemp -t spacecrunch-palette).png"
trap 'rm -f "$CONCAT" "$SEL" "$PALETTE"' EXIT

# The frames are all the same size, so the output height is derived once from
# the first frame. `scale=WIDTH:-1` (with a single dash) is what asks ffmpeg
# to preserve the aspect ratio; the two-dash form is not a valid height and
# collapses the picture to a one-pixel line.
HEIGHT="$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
  -of csv=p=0 "$FRAMES_DIR/0000.png")"
if [[ -z "$HEIGHT" ]]; then
  echo "error: could not read the frame height" >&2
  exit 1
fi
SCALE="scale=$WIDTH:-1:flags=lanczos"

# The concat manifest already carries each frame's hold time, so the frames
# are *not* resampled to a constant rate — that would multiply the tour into
# hundreds of near-identical frames and blow the file up. Each captured frame
# is one GIF frame, held for exactly as long as the tour intended.
#
# Two passes: the first builds a palette from the frames, the second applies
# it. A single-pass GIF quantises per frame, which makes the colours flicker.
ffmpeg -y -loglevel error \
  -f concat -safe 0 -i "$CONCAT" \
  -vf "$SCALE,palettegen=max_colors=$COLORS:stats_mode=diff" \
  "$PALETTE"

ffmpeg -y -loglevel error \
  -f concat -safe 0 -i "$CONCAT" -i "$PALETTE" \
  -filter_complex \
    "[0:v]$SCALE[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 "$OUTPUT"

echo "==> Built $OUTPUT"
ls -lh "$OUTPUT"

