#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERED_CASK="$(mktemp "${TMPDIR:-/tmp}/cue-notchpad-cask.XXXXXX")"
cleanup() {
    rm -f "$RENDERED_CASK"
}
trap cleanup EXIT

cd "$ROOT"

bash -n Scripts/*.sh
./Scripts/render-homebrew-cask.sh \
    0.0.0 0000000000000000000000000000000000000000000000000000000000000000 \
    "$RENDERED_CASK"
ruby -c "$RENDERED_CASK"
grep -q 'version "0.0.0"' "$RENDERED_CASK"
grep -q 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$RENDERED_CASK"
grep -q 'postflight_steps do' "$RENDERED_CASK"
! grep -q 'postflight do' "$RENDERED_CASK"
grep -q 'if_path_exists "{{appdir}}/Cue Notchpad.app" do' "$RENDERED_CASK"
grep -q 'run "/usr/bin/xattr"' "$RENDERED_CASK"

python3 - <<'PY'
import json
from pathlib import Path

compile(Path("Scripts/generate-tokenizer-index.py").read_text(), "generate-tokenizer-index.py", "exec")

fixtures = Path("Tests/Fixtures/Persistence")
for name, version in (("config-v1.json", 1), ("config-v2.json", 2), ("usage-v1.json", 1)):
    document = json.loads((fixtures / name).read_text())
    assert document["schemaVersion"] == version, name

future_usage = json.loads((fixtures / "usage-future.json").read_text())
future_config = json.loads((fixtures / "config-future.json").read_text())
corrupt_v2 = json.loads((fixtures / "config-v2-corrupt-provider-keys.json").read_text())
assert future_usage["schemaVersion"] > 1
assert future_config["schemaVersion"] > 2
assert corrupt_v2["schemaVersion"] == 2
assert not isinstance(corrupt_v2["providerAPIKeys"], dict)

for name in ("config-corrupt.json", "usage-corrupt.json"):
    try:
        json.loads((fixtures / name).read_text())
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError(f"{name} must remain corrupt")
PY

plutil -lint Supporting/Info.plist
plutil -lint Sources/CueCore/Resources/en.lproj/Localizable.strings
plutil -lint Sources/CueCore/Resources/zh-Hans.lproj/Localizable.strings
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Supporting/Info.plist)" == \
    "io.github.haotzops.cue-notchpad" ]]

printf 'Source metadata and scripts are valid.\n'
