#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
APP="$OUTPUT_DIR/Cue Notepad.app"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product cue
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/cue" "$APP/Contents/MacOS/cue"
cp "$ROOT/Supporting/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Supporting/ThirdPartyNotices.txt" "$APP/Contents/Resources/"

# SwiftPM compiles target resources into sibling bundles. Flatten their
# localized folders into the conventional app-bundle Resources directory so
# Bundle.main and localized Info.plist values both work after installation.
shopt -s nullglob
for resource_bundle in "$BIN_DIR"/CueNotepad_*.bundle; do
    for localization in "$resource_bundle"/*.lproj; do
        cp -R "$localization" "$APP/Contents/Resources/"
    done
    for resource in "$resource_bundle"/*.tiktoken; do
        cp "$resource" "$APP/Contents/Resources/"
    done
done
shopt -u nullglob

chmod +x "$APP/Contents/MacOS/cue"

# An ad-hoc signature avoids the "bundle format is ambiguous" warning and is
# sufficient for local builds. A release identity can be supplied by setting
# CODE_SIGN_IDENTITY.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
fi

printf 'Built %s\n' "$APP"
