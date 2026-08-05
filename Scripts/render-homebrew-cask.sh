#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
SHA256="${2:-}"
OUTPUT="${3:-}"
TEMPLATE="$ROOT/Packaging/homebrew/cue-notchpad.rb.template"

if [[ -z "$VERSION" || -z "$SHA256" || -z "$OUTPUT" ]]; then
    printf 'Usage: %s VERSION SHA256 OUTPUT\n' "$0" >&2
    exit 2
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Invalid version: %s\n' "$VERSION" >&2
    exit 2
}
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'Invalid SHA-256: %s\n' "$SHA256" >&2
    exit 2
}

python3 - "$TEMPLATE" "$VERSION" "$SHA256" "$OUTPUT" <<'PY'
import os
from pathlib import Path
import sys
import tempfile

template_path = Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
output_path = Path(sys.argv[4])
content = template_path.read_text()
replacements = {
    "@VERSION@": version,
    "@SHA256@": sha256,
}
for placeholder, value in replacements.items():
    if content.count(placeholder) != 1:
        raise SystemExit(f"Expected exactly one {placeholder} placeholder in {template_path}")
    content = content.replace(placeholder, value)

output_path.parent.mkdir(parents=True, exist_ok=True)
file_descriptor, temporary_name = tempfile.mkstemp(
    dir=output_path.parent,
    prefix=f".{output_path.name}.",
)
try:
    with os.fdopen(file_descriptor, "w") as temporary_file:
        temporary_file.write(content)
    os.replace(temporary_name, output_path)
except BaseException:
    Path(temporary_name).unlink(missing_ok=True)
    raise
PY

printf 'Rendered Homebrew Cask: %s\n' "$OUTPUT"
