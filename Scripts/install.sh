#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APP_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SOURCE_APP="$ROOT/build/Cue Notepad.app"
TARGET_APP="$APP_DIR/Cue Notepad.app"

"$ROOT/Scripts/build-app.sh"
mkdir -p "$APP_DIR" "$BIN_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

# Do not symlink the Mach-O executable directly. macOS then sees argv[0] as
# ~/.local/bin/cue and loses the enclosing app bundle identity, which breaks
# activation and localization. A tiny launcher preserves the real app path.
rm -f "$BIN_DIR/cue"
printf '#!/bin/sh\nexec "%s" "$@"\n' \
    "$TARGET_APP/Contents/MacOS/cue" > "$BIN_DIR/cue"
chmod +x "$BIN_DIR/cue"

printf 'Installed app: %s\n' "$TARGET_APP"
printf 'Installed command: %s/cue\n' "$BIN_DIR"
printf 'Make sure %s is in PATH.\n' "$BIN_DIR"
