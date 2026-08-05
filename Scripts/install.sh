#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APP_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SOURCE_APP="$ROOT/build/Cue Notchpad.app"
TARGET_APP="$APP_DIR/Cue Notchpad.app"
RELEASE_ARCHIVE="${RELEASE_ARCHIVE:-}"
EXTRACT_DIR=""
PREFERENCES_DOMAIN="io.github.haotzops.cue-notchpad"
PREFERENCES_BACKUP="$(mktemp "${TMPDIR:-/tmp}/cue-preferences.XXXXXX.plist")"
HAVE_PREFERENCES=0
cleanup() {
    rm -f "$PREFERENCES_BACKUP"
    [[ -z "$EXTRACT_DIR" ]] || rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

# An installation is never a settings reset. Preserve the complete preference
# domain explicitly, including future settings that Cue may add.
if defaults export "$PREFERENCES_DOMAIN" "$PREFERENCES_BACKUP" 2>/dev/null; then
    HAVE_PREFERENCES=1
fi

if [[ -n "$RELEASE_ARCHIVE" ]]; then
    [[ -f "$RELEASE_ARCHIVE" ]] || {
        printf 'Release archive does not exist: %s\n' "$RELEASE_ARCHIVE" >&2
        exit 2
    }
    EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cue-release.XXXXXX")"
    ditto -x -k "$RELEASE_ARCHIVE" "$EXTRACT_DIR"
    SOURCE_APP="$EXTRACT_DIR/Cue Notchpad.app"
    [[ -d "$SOURCE_APP" ]] || {
        printf 'Release archive does not contain Cue Notchpad.app: %s\n' "$RELEASE_ARCHIVE" >&2
        exit 2
    }
else
    "$ROOT/Scripts/build-app.sh"
fi

mkdir -p "$APP_DIR" "$BIN_DIR"
# Keep the application directory in place. Removing and recreating a bundle can
# make Launch Services treat it as a new installation and is unnecessary for an
# update; ditto replaces bundle contents without touching user preferences.
ditto "$SOURCE_APP" "$TARGET_APP"

if [[ "$HAVE_PREFERENCES" == 1 ]]; then
    defaults import "$PREFERENCES_DOMAIN" "$PREFERENCES_BACKUP"
fi

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
