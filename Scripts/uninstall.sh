#!/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TARGET_APP="$APP_DIR/Cue Notchpad.app"
LAUNCHER="$BIN_DIR/cue"

if [[ -e "$TARGET_APP" ]]; then
    rm -rf "$TARGET_APP"
    printf 'Removed app: %s\n' "$TARGET_APP"
else
    printf 'App not found: %s\n' "$TARGET_APP"
fi

# Remove only the launcher produced by install.sh. A user-owned cue command in
# the same directory must not be removed merely because this target is used.
expected_launcher="$(printf '#!/bin/sh\nexec "%s" "$@"\n' "$TARGET_APP/Contents/MacOS/cue")"
if [[ -f "$LAUNCHER" ]] && [[ "$(<"$LAUNCHER")" == "$expected_launcher" ]]; then
    rm -f "$LAUNCHER"
    printf 'Removed command: %s\n' "$LAUNCHER"
elif [[ -e "$LAUNCHER" ]]; then
    printf 'Left unrelated command untouched: %s\n' "$LAUNCHER"
else
    printf 'Command not found: %s\n' "$LAUNCHER"
fi
