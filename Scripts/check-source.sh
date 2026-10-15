#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERED_CASK="$(mktemp "${TMPDIR:-/tmp}/cue-notchpad-cask.XXXXXX")"
FAKE_PGREP="$(mktemp "${TMPDIR:-/tmp}/cue-notchpad-pgrep.XXXXXX")"
cleanup() {
    rm -f "$RENDERED_CASK" "$FAKE_PGREP"
}
trap cleanup EXIT

cd "$ROOT"

bash -n Scripts/*.sh
cat > "$FAKE_PGREP" <<'EOF'
#!/bin/sh
exit "${CUE_PGREP_EXIT:-1}"
EOF
chmod +x "$FAKE_PGREP"
CUE_PGREP="$FAKE_PGREP" CUE_PGREP_EXIT=1 ./Scripts/ensure-cue-not-running.sh
if CUE_PGREP="$FAKE_PGREP" CUE_PGREP_EXIT=0 ./Scripts/ensure-cue-not-running.sh; then
    printf 'ensure-cue-not-running.sh failed to block an active host.\n' >&2
    exit 1
fi
./Scripts/render-homebrew-cask.sh \
    0.0.0 0000000000000000000000000000000000000000000000000000000000000000 \
    "$RENDERED_CASK"
ruby -c "$RENDERED_CASK"
grep -q 'version "0.0.0"' "$RENDERED_CASK"
grep -q 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$RENDERED_CASK"
grep -q 'preflight do' "$RENDERED_CASK"
grep -q '"/usr/bin/pgrep"' "$RENDERED_CASK"
grep -q 'postflight_steps do' "$RENDERED_CASK"
! grep -q 'postflight do' "$RENDERED_CASK"
grep -q 'if_path_exists "{{appdir}}/Cue Notchpad.app" do' "$RENDERED_CASK"
grep -q 'run "/usr/bin/xattr"' "$RENDERED_CASK"
grep -q 'depends_on macos: :tahoe' "$RENDERED_CASK"
grep -q 'swift-tools-version: 6.2' Package.swift
grep -q 'platforms: \[.macOS(.v26)\]' Package.swift

python3 - <<'PY'
import json
from pathlib import Path

compile(Path("Scripts/generate-tokenizer-index.py").read_text(), "generate-tokenizer-index.py", "exec")

fixtures = Path("Tests/Fixtures/Persistence")
legacy_config = json.loads((fixtures / "config-legacy.json").read_text())
provider_keys_config = json.loads((fixtures / "config-provider-keys.json").read_text())
assert "schemaVersion" not in legacy_config
assert "schemaVersion" not in provider_keys_config
assert isinstance(provider_keys_config["providerAPIKeys"], dict)

provider_profiles = json.loads((fixtures / "provider-profiles-v1.json").read_text())
corrupt_provider_keys = json.loads((fixtures / "config-corrupt-provider-keys.json").read_text())
assert provider_profiles["schemaVersion"] == 1
assert provider_profiles["activeProfileID"] in {profile["id"] for profile in provider_profiles["profiles"]}
assert not isinstance(corrupt_provider_keys["providerAPIKeys"], dict)

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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Supporting/Info.plist)" == "26.0" ]]

printf 'Source metadata and scripts are valid.\n'
