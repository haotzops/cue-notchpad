#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RECORDINGS="$ROOT/public/recordings"
RECORDING=""
OUT="$ROOT/out"

for candidate in "$RECORDINGS"/screen-demo-*.mp4; do
  [[ -s "$candidate" ]] || continue
  if [[ -z "$RECORDING" || "$candidate" -nt "$RECORDING" ]]; then
    RECORDING="$candidate"
  fi
done

if [[ -z "$RECORDING" && "${ALLOW_STORYBOARD:-0}" != "1" ]]; then
  echo "No screen capture found at public/recordings/screen-demo-*.mp4." >&2
  echo "Record the real macOS demo first, or set ALLOW_STORYBOARD=1 for the clearly marked animatic." >&2
  exit 1
fi
TRIM_BEFORE_FRAMES=0
RECORDING_DURATION_FRAMES=780
if [[ -n "$RECORDING" ]]; then
  SOURCE_DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$RECORDING")"
  TRIM_START="${CUE_DEMO_TRIM_START_SECONDS:-0}"
  TRIM_END="${CUE_DEMO_TRIM_END_SECONDS:-$SOURCE_DURATION}"
  CUT_DURATION="$(awk -v start="$TRIM_START" -v end="$TRIM_END" 'BEGIN { print end - start }')"
  if ! awk -v start="$TRIM_START" -v end="$TRIM_END" -v source="$SOURCE_DURATION" 'BEGIN { exit !(start >= 0 && end > start && end <= source) }'; then
    echo "Invalid trim range: start=$TRIM_START end=$TRIM_END source_duration=$SOURCE_DURATION" >&2
    exit 1
  fi
  TRIM_BEFORE_FRAMES="$(awk -v seconds="$TRIM_START" 'BEGIN { printf "%d", seconds * 30 + 0.5 }')"
  RECORDING_DURATION_FRAMES="$(awk -v seconds="$CUT_DURATION" 'BEGIN { printf "%d", seconds * 30 + 0.5 }')"
fi
mkdir -p "$OUT"
RENDER_PROPS=()
if [[ -n "$RECORDING" ]]; then
  RECORDING_NAME="recordings/$(basename "$RECORDING")"
  RENDER_PROPS=(--props "{\"recorded\":true,\"recordingFile\":\"$RECORDING_NAME\",\"recordingDurationFrames\":$RECORDING_DURATION_FRAMES,\"trimBeforeFrames\":$TRIM_BEFORE_FRAMES}")
fi
npx remotion render src/index.ts DemoCut "$OUT/cue-notchpad-demo.mp4" \
  --codec h264 --crf 18 --pixel-format yuv420p "${RENDER_PROPS[@]}"
npx remotion still src/index.ts Cover "$OUT/cue-notchpad-cover.png" --frame=0
ffmpeg -y -hide_banner -loglevel error -i "$OUT/cue-notchpad-demo.mp4" \
  -vf 'fps=10,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3' \
  -loop 0 "$OUT/cue-notchpad-preview.gif"
if [[ -z "$RECORDING" ]]; then
  touch "$OUT/STORYBOARD-ONLY-NOT-A-PRODUCT-DEMO.txt"
  echo "Rendered a marked animatic. It does not contain an app screen recording." >&2
else
  rm -f "$OUT/STORYBOARD-ONLY-NOT-A-PRODUCT-DEMO.txt"
  echo "Used latest screen recording: $(basename "$RECORDING")"
  echo "Used source range ${TRIM_START}s–${TRIM_END}s (${CUT_DURATION}s)."
fi
echo "Wrote MP4, GIF, and PNG cover to $OUT"
