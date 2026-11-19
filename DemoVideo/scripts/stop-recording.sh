#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDINGS="$ROOT/public/recordings"
PIDFILE="$RECORDINGS/.screen-demo.pid"
OUTPUTFILE="$RECORDINGS/.screen-demo.output"

if [[ ! -f "$PIDFILE" ]]; then
  echo "No Cue demo recording is running." >&2
  exit 1
fi
PID="$(cat "$PIDFILE")"
if [[ ! -f "$OUTPUTFILE" ]]; then
  echo "Recording output path is missing; refusing to guess which take to finalize." >&2
  exit 1
fi
OUTPUT="$(cat "$OUTPUTFILE")"
case "$OUTPUT" in
  "$RECORDINGS"/screen-demo-*.mp4) ;;
  *) echo "Unexpected recording output path. Refusing to finalize it." >&2; exit 1 ;;
esac
LOGFILE="${OUTPUT%.mp4}.log"
kill -INT "$PID" 2>/dev/null || true
for _ in $(seq 1 30); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.25
done
rm -f "$PIDFILE" "$OUTPUTFILE"
if [[ ! -s "$OUTPUT" ]]; then
  echo "No recording was finalized. Capture log:" >&2
  tail -40 "$LOGFILE" >&2 || true
  exit 1
fi
if ! ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$OUTPUT" 2>/dev/null | rg -q '^1920x1080$'; then
  echo "Recording exists but is not 1920x1080. Review $LOGFILE." >&2
  exit 1
fi
duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")"
echo "Saved and verified screen recording: $OUTPUT"
echo "Duration: ${duration}s"
