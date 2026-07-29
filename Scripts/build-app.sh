#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
APP="$OUTPUT_DIR/Cue Notchpad.app"
INFO_PLIST="$ROOT/Supporting/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
RELEASE_VERSION="${RELEASE_VERSION:-$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$INFO_PLIST")}"
ARCHS="${ARCHS:-}"
MINIMUM_MACOS_VERSION="${MINIMUM_MACOS_VERSION:-13.0}"

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Invalid RELEASE_VERSION: %s\n' "$RELEASE_VERSION" >&2
    exit 2
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BUILD_NUMBER must be a positive integer: %s\n' "$BUILD_NUMBER" >&2
    exit 2
}

cd "$ROOT"
"$ROOT/Scripts/generate-tokenizer-index.py"

RESOURCE_BIN_DIR=""
if [[ -z "$ARCHS" ]]; then
    swift build -c "$CONFIGURATION" --product cue
    swift build -c "$CONFIGURATION" --product cue-host
    RESOURCE_BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

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
        build_args=(-c "$CONFIGURATION" --triple "$triple" --scratch-path "$scratch_path")
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

cp "$INFO_PLIST" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Supporting/cue-logo.icns" "$APP/Contents/Resources/cue-logo.icns"
cp "$ROOT/Supporting/ThirdPartyNotices.txt" "$APP/Contents/Resources/"
[[ ! -f "$ROOT/LICENSE" ]] || cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

# SwiftPM compiles target resources into sibling bundles. Flatten their
# localized folders into the conventional app-bundle Resources directory so
# Bundle.main and localized Info.plist values both work after installation.
shopt -s nullglob
for resource_bundle in "$RESOURCE_BIN_DIR"/CueNotchpad_*.bundle; do
    for localization in "$resource_bundle"/*.lproj; do
        cp -R "$localization" "$APP/Contents/Resources/"
    done
    for resource in "$resource_bundle"/*.cuebpe; do
        cp "$resource" "$APP/Contents/Resources/"
    done
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
