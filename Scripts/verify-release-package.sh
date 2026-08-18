#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
VERSION="${RELEASE_VERSION:-${1:-}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
ARCHIVE_NAME="Cue-Notchpad-${VERSION}-macOS-arm64.zip"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
PROVENANCE="$DIST_DIR/PROVENANCE.json"
EXTRACT_DIR=""
cleanup() {
    [[ -z "$EXTRACT_DIR" ]] || rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Usage: RELEASE_VERSION=x.y.z BUILD_NUMBER=n %s\n' "$0" >&2
    exit 2
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BUILD_NUMBER must be a positive integer: %s\n' "$BUILD_NUMBER" >&2
    exit 2
}
[[ -f "$ARCHIVE" ]] || {
    printf 'Release archive does not exist: %s\n' "$ARCHIVE" >&2
    exit 2
}
[[ -f "$DIST_DIR/SHA256SUMS" && -f "$PROVENANCE" ]] || {
    printf 'Release metadata is incomplete in %s\n' "$DIST_DIR" >&2
    exit 2
}

(
    cd "$DIST_DIR"
    shasum -a 256 -c SHA256SUMS
)
unzip -t "$ARCHIVE" >/dev/null

EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cue-release-check.XXXXXX")"
ditto -x -k "$ARCHIVE" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/Cue Notchpad.app"
[[ -d "$APP" ]] || {
    printf '%s does not contain Cue Notchpad.app\n' "$ARCHIVE" >&2
    exit 1
}

plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
for resource in cue-logo.icns ThirdPartyNotices.txt LICENSE.txt index.ts BuildInfo.json; do
    [[ -f "$APP/Contents/Resources/$resource" ]] || {
        printf 'Release app is missing resource: %s\n' "$resource" >&2
        exit 1
    }
done
cmp "$ROOT/Sources/CueCore/Resources/PiIntegration/pi-cue-context/index.ts" \
    "$APP/Contents/Resources/index.ts"
cmp "$PROVENANCE" "$APP/Contents/Resources/BuildInfo.json"

[[ "$($PLIST_BUDDY -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == \
    "io.github.haotzops.cue-notchpad" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == \
    "$VERSION" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == \
    "$BUILD_NUMBER" ]]

python3 - "$PROVENANCE" "$VERSION" "$BUILD_NUMBER" <<'PY'
import json
from pathlib import Path
import sys

document = json.loads(Path(sys.argv[1]).read_text())
assert document["schemaVersion"] == 1
assert document["version"] == sys.argv[2]
assert document["buildNumber"] == int(sys.argv[3])
assert document["configuration"] == "release"
assert document["architectures"] == ["arm64"]
PY

for executable in cue cue-host; do
    archs="$(xcrun lipo -archs "$APP/Contents/MacOS/$executable")"
    [[ "$archs" == "arm64" ]] || {
        printf '%s has unexpected architectures: %s\n' "$executable" "$archs" >&2
        exit 1
    }
done

set +e
"$APP/Contents/MacOS/cue" --invalid-option >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 64 ]] || {
    printf 'Release CLI smoke test returned %s instead of 64.\n' "$status" >&2
    exit 1
}

printf 'Verified release package: %s\n' "$ARCHIVE"
