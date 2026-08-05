#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-${1:-}}"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://github.com/haotzops/cue-notchpad/releases/download}"
ARCHIVE_NAME="Cue-Notchpad-${VERSION}-macOS-arm64.zip"
RELEASE_URL="$RELEASE_BASE_URL/v$VERSION"
TEMPORARY_DIR=""
cleanup() {
    [[ -z "$TEMPORARY_DIR" ]] || rm -rf "$TEMPORARY_DIR"
}
trap cleanup EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Usage: VERSION=x.y.z %s\n' "$0" >&2
    exit 2
}

TEMPORARY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cue-published-release.XXXXXX")"
archive="$TEMPORARY_DIR/$ARCHIVE_NAME"
checksums="$TEMPORARY_DIR/SHA256SUMS"
expected_checksums="$TEMPORARY_DIR/expected-SHA256SUMS"

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$archive" "$RELEASE_URL/$ARCHIVE_NAME"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$checksums" "$RELEASE_URL/SHA256SUMS"

awk -v archive="$ARCHIVE_NAME" '
    $2 == archive { print $1 "  " $2; found = 1 }
    END { exit(found ? 0 : 1) }
' "$checksums" > "$expected_checksums" || {
    printf 'SHA256SUMS does not contain %s\n' "$ARCHIVE_NAME" >&2
    exit 1
}
(
    cd "$TEMPORARY_DIR"
    shasum -a 256 -c "$(basename "$expected_checksums")"
)

RELEASE_ARCHIVE="$archive" "$ROOT/Scripts/install.sh"
