#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
APP="$OUTPUT_DIR/Cue Notchpad.app"
INFO_PLIST="$ROOT/Supporting/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
RELEASE_VERSION="${RELEASE_VERSION:-$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$INFO_PLIST")}"
ARCHS="${ARCHS:-arm64}"
MINIMUM_MACOS_VERSION="26.0"
SOURCE_REVISION="${SOURCE_REVISION:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')}"
SOURCE_DIRTY=false
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null || true)" ]]; then
    SOURCE_DIRTY=true
fi

[[ "$CONFIGURATION" == "debug" || "$CONFIGURATION" == "release" ]] || {
    printf 'Unsupported CONFIGURATION: %s\n' "$CONFIGURATION" >&2
    exit 2
}
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Invalid RELEASE_VERSION: %s\n' "$RELEASE_VERSION" >&2
    exit 2
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BUILD_NUMBER must be a positive integer: %s\n' "$BUILD_NUMBER" >&2
    exit 2
}

cd "$ROOT"
# SwiftPM's link-only Clang invocation needs -isysroot as a Clang linker
# argument; --sdk alone leaves LC_BUILD_VERSION's SDK at the deployment target.
SDKROOT="$(xcrun --show-sdk-path)"
sdk_args=(
    --sdk "$SDKROOT"
    -Xswiftc -Xclang-linker -Xswiftc -isysroot
    -Xswiftc -Xclang-linker -Xswiftc "$SDKROOT"
)
"$ROOT/Scripts/generate-tokenizer-index.py"

RESOURCE_BIN_DIR=""
if [[ -z "$ARCHS" ]]; then
    swift build -c "$CONFIGURATION" "${sdk_args[@]}" --product cue
    swift build -c "$CONFIGURATION" "${sdk_args[@]}" --product cue-host
    RESOURCE_BIN_DIR="$(swift build -c "$CONFIGURATION" "${sdk_args[@]}" --show-bin-path)"

    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$RESOURCE_BIN_DIR/cue" "$APP/Contents/MacOS/cue"
    cp "$RESOURCE_BIN_DIR/cue-host" "$APP/Contents/MacOS/cue-host"
else
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

    cue_binaries=()
    host_binaries=()
    for arch in $ARCHS; do
        case "$arch" in
            arm64|x86_64) ;;
            *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 2 ;;
        esac

        scratch_path="$ROOT/.build/release-$arch"
        triple="$arch-apple-macosx$MINIMUM_MACOS_VERSION"
        build_args=(-c "$CONFIGURATION" --triple "$triple" --scratch-path "$scratch_path" "${sdk_args[@]}")
        swift build "${build_args[@]}" --product cue
        swift build "${build_args[@]}" --product cue-host
        bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
        cue_binaries+=("$bin_dir/cue")
        host_binaries+=("$bin_dir/cue-host")
        [[ -n "$RESOURCE_BIN_DIR" ]] || RESOURCE_BIN_DIR="$bin_dir"
    done

    if [[ ${#cue_binaries[@]} -eq 1 ]]; then
        cp "${cue_binaries[0]}" "$APP/Contents/MacOS/cue"
        cp "${host_binaries[0]}" "$APP/Contents/MacOS/cue-host"
    else
        xcrun lipo -create "${cue_binaries[@]}" -output "$APP/Contents/MacOS/cue"
        xcrun lipo -create "${host_binaries[@]}" -output "$APP/Contents/MacOS/cue-host"
    fi
fi

# A recent SDK in LC_BUILD_VERSION is required for native system appearance on
# Keep the binary deployment target aligned with the package and app bundle baseline.
python3 - "$APP/Contents/MacOS/cue-host" "$MINIMUM_MACOS_VERSION" "$SDKROOT" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

binary, minimum, sdk_root = sys.argv[1:]
actual = subprocess.check_output(["xcrun", "vtool", "-show-build", binary], text=True)
version = json.loads(Path(sdk_root, "SDKSettings.json").read_text())["Version"]
if f"minos {minimum}" not in actual or f"sdk {version}" not in actual:
    raise SystemExit(f"Incorrect cue-host platform version (expected minOS {minimum}, SDK {version}):\n{actual}")
PY

cp "$INFO_PLIST" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
"$ROOT/Scripts/generate-app-icon.sh" "$ROOT/Supporting/logo.svg" "$APP/Contents/Resources/cue-logo.icns"
cp "$ROOT/Supporting/ThirdPartyNotices.txt" "$APP/Contents/Resources/"
[[ ! -f "$ROOT/LICENSE" ]] || cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

export ARCHS BUILD_NUMBER CONFIGURATION MINIMUM_MACOS_VERSION RELEASE_VERSION SOURCE_DIRTY SOURCE_REVISION
python3 - "$APP/Contents/Resources/BuildInfo.json" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys


def command_output(*command):
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None

metadata = {
    "schemaVersion": 1,
    "version": os.environ["RELEASE_VERSION"],
    "buildNumber": int(os.environ["BUILD_NUMBER"]),
    "configuration": os.environ["CONFIGURATION"],
    "architectures": os.environ["ARCHS"].split(),
    "minimumMacOSVersion": os.environ["MINIMUM_MACOS_VERSION"],
    "sourceRevision": os.environ["SOURCE_REVISION"],
    "sourceDirty": os.environ["SOURCE_DIRTY"] == "true",
    "swiftVersion": command_output("swift", "--version"),
    "xcodeVersion": command_output("xcodebuild", "-version"),
}
Path(sys.argv[1]).write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
PY

# SwiftPM compiles target resources into sibling bundles. Flatten every runtime
# resource into the conventional app Resources directory; only SwiftPM's bundle
# metadata is excluded. New resource types therefore ship without another
# extension allowlist.
shopt -s nullglob
for resource_bundle in "$RESOURCE_BIN_DIR"/CueNotchpad_*.bundle; do
    # SwiftPM may emit a flat resource directory or a macOS bundle with the
    # runtime files under Contents/Resources. Copy only runtime resources into
    # the app's conventional Resources directory; bundle metadata and code
    # signatures must not become nested app resources.
    resource_root="$resource_bundle"
    if [[ -d "$resource_bundle/Contents/Resources" ]]; then
        resource_root="$resource_bundle/Contents/Resources"
    fi

    while IFS= read -r -d '' resource; do
        relative_path="${resource#"$resource_root/"}"
        destination="$APP/Contents/Resources/$relative_path"
        mkdir -p "$(dirname "$destination")"
        cp -R "$resource" "$destination"
    done < <(find "$resource_root" -mindepth 1 -maxdepth 1 -print0)
done
shopt -u nullglob

chmod +x "$APP/Contents/MacOS/cue" "$APP/Contents/MacOS/cue-host"

# Ad-hoc signing is the default for local and preview builds. Set
# CODE_SIGN_IDENTITY to a Developer ID identity if one becomes available.
if command -v codesign >/dev/null 2>&1; then
    identity="${CODE_SIGN_IDENTITY:--}"
    codesign --force --sign "$identity" "$APP/Contents/MacOS/cue"
    codesign --force --sign "$identity" "$APP/Contents/MacOS/cue-host"
    codesign --force --sign "$identity" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

printf 'Built %s (version %s, build %s)\n' "$APP" "$RELEASE_VERSION" "$BUILD_NUMBER"
