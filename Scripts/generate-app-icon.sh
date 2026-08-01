#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/Supporting/logo.svg}"
OUTPUT="${2:-$ROOT/build/cue-logo.icns}"

[[ -f "$SOURCE" ]] || { printf 'Icon source does not exist: %s\n' "$SOURCE" >&2; exit 2; }
command -v qlmanage >/dev/null || { printf 'qlmanage is required to render SVG icons\n' >&2; exit 2; }
command -v iconutil >/dev/null || { printf 'iconutil is required to build ICNS icons\n' >&2; exit 2; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
qlmanage -t -s 1024 -o "$workdir" "$SOURCE" >/dev/null
rendered="$workdir/$(basename "$SOURCE").png"
[[ -f "$rendered" ]] || { printf 'Failed to render SVG icon: %s\n' "$SOURCE" >&2; exit 1; }

iconset="$workdir/Cue.iconset"
mkdir "$iconset"
for entry in '16:16' '16@2x:32' '32:32' '32@2x:64' '128:128' '128@2x:256' '256:256' '256@2x:512' '512:512' '512@2x:1024'; do
    name="${entry%%:*}"
    pixels="${entry##*:}"
    sips -z "$pixels" "$pixels" "$rendered" --out "$iconset/icon_${name}x${name%%@*}.png" >/dev/null
    if [[ "$name" == *'@2x' ]]; then
        base="${name%@2x}"
        mv "$iconset/icon_${name}x${base}.png" "$iconset/icon_${base}x${base}@2x.png"
    fi
done

mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$iconset" -o "$OUTPUT"
