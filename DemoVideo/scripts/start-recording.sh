#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDINGS="$ROOT/public/recordings"
REQUESTED_DEVICE="${1:-${CUE_DEMO_SCREEN_DEVICE:-}}"
PIDFILE="$RECORDINGS/.screen-demo.pid"
OUTPUTFILE="$RECORDINGS/.screen-demo.output"

mkdir -p "$RECORDINGS"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "A Cue demo recording is already running (PID $(cat "$PIDFILE"))." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required. Install it with Homebrew before recording." >&2
  exit 1
fi

DEVICE_LIST="$(ffmpeg -hide_banner -f avfoundation -list_devices true -i '' 2>&1 || true)"
SCREEN_DEVICES="$(printf '%s\n' "$DEVICE_LIST" | sed -nE 's/.*\[([0-9]+)\] Capture screen ([0-9]+).*/\1 \2/p')"
if [[ -z "$SCREEN_DEVICES" ]]; then
  echo "No AVFoundation screen-capture device was found. No recording was started." >&2
  printf '%s\n' "$DEVICE_LIST" | rg 'AVFoundation video devices|\[[0-9]+\]' >&2 || true
  exit 1
fi

if [[ -n "$REQUESTED_DEVICE" ]]; then
  DEVICE="$(printf '%s\n' "$SCREEN_DEVICES" | awk -v requested="$REQUESTED_DEVICE" '$1 == requested { print $1; exit }')"
  if [[ -z "$DEVICE" ]]; then
    echo "Device $REQUESTED_DEVICE is not an AVFoundation screen-capture device; refusing to record." >&2
    printf '%s\n' "$SCREEN_DEVICES" | awk '{ printf "Screen device index %s (display %s)\n", $1, $2 }' >&2
    exit 1
  fi
else
  DEVICE="$(printf '%s\n' "$SCREEN_DEVICES" | awk '$2 == 0 { print $1; exit }')"
  DEVICE="${DEVICE:-$(printf '%s\n' "$SCREEN_DEVICES" | awk 'NR == 1 { print $1; exit }')}"
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT="$RECORDINGS/screen-demo-$STAMP.mp4"
LOGFILE="$RECORDINGS/.screen-demo-$STAMP.log"

ffmpeg -hide_banner -nostdin \
  -f avfoundation -framerate 30 -capture_cursor 1 \
  -i "$DEVICE:none" \
  -vf 'scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2' \
  -an -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$OUTPUT" >"$LOGFILE" 2>&1 &
PID=$!
printf '%s\n' "$PID" > "$PIDFILE"
printf '%s\n' "$OUTPUT" > "$OUTPUTFILE"
sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
  rm -f "$PIDFILE" "$OUTPUTFILE"
  echo "Screen capture could not start. Check macOS Screen Recording permission and available AVFoundation display devices." >&2
  tail -40 "$LOGFILE" >&2
  exit 1
fi
echo "Recording started from screen device $DEVICE."
echo "This take is saved to: $OUTPUT"
echo "Run the demo flow now. Stop with: npm run record:stop"
echo "Screen video only; no microphone or system audio is saved."
