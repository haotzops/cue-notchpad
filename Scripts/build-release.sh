#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${RELEASE_VERSION:-${1:-}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
STAGING_DIR="$DIST_DIR/.staging"
APP_NAME="Cue Notchpad.app"
ARCHIVE_NAME="Cue-Notchpad-${VERSION}-macOS-universal.zip"

if [[ -z "$VERSION" ]]; then
    printf 'Usage: RELEASE_VERSION=0.1.0 BUILD_NUMBER=1 %s\n' "$0" >&2
    exit 2
fi
for required_arch in arm64 x86_64; do
    [[ " $ARCHS " == *" $required_arch "* ]] || {
        printf 'Release archives must include arm64 and x86_64 (ARCHS=%s)\n' "$ARCHS" >&2
        exit 2
    }
done

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
rm -f "$DIST_DIR"/*.zip "$DIST_DIR/SHA256SUMS"

RELEASE_VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
ARCHS="$ARCHS" \
OUTPUT_DIR="$STAGING_DIR" \
CONFIGURATION=release \
    "$ROOT/Scripts/build-app.sh"

for executable in cue cue-host; do
    binary="$STAGING_DIR/$APP_NAME/Contents/MacOS/$executable"
    actual_archs="$(xcrun lipo -archs "$binary")"
    for expected_arch in $ARCHS; do
        [[ " $actual_archs " == *" $expected_arch "* ]] || {
            printf '%s is missing architecture %s (found: %s)\n' "$executable" "$expected_arch" "$actual_archs" >&2
            exit 1
        }
    done
done

/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "$STAGING_DIR/$APP_NAME" "$DIST_DIR/$ARCHIVE_NAME"
(
    cd "$DIST_DIR"
    shasum -a 256 "$ARCHIVE_NAME" > SHA256SUMS
)
rm -rf "$STAGING_DIR"

printf 'Prepared release assets:\n  %s\n  %s\n' \
    "$DIST_DIR/$ARCHIVE_NAME" "$DIST_DIR/SHA256SUMS"
