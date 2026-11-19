#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTENSION_SOURCE="$ROOT/../Sources/CueCore/Resources/PiIntegration/pi-cue-context/index.ts"
PROFILE_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/cue-notchpad-pi-demo.XXXXXX")"
AGENT_DIR="$PROFILE_DIR/agent"
EXTENSION_DIR="$AGENT_DIR/extensions/pi-cue-context"

mkdir -p "$EXTENSION_DIR"
chmod 700 "$PROFILE_DIR" "$AGENT_DIR" "$AGENT_DIR/extensions" "$EXTENSION_DIR"
cp "$EXTENSION_SOURCE" "$EXTENSION_DIR/index.ts"
chmod 600 "$EXTENSION_DIR/index.ts"
cat > "$AGENT_DIR/settings.json" <<'JSON'
{
  "externalEditor": "cue --wait"
}
JSON
chmod 600 "$AGENT_DIR/settings.json"

cat > "$PROFILE_DIR/demo-prompt.txt" <<'PROMPT'
Use a fictional sample project only. Ask Pi to draft one concise README tagline
for a command-line note-taking app. Do not include personal, client, or company
information. After Pi answers, press Control-G to open Cue and edit that prompt.
PROMPT
chmod 600 "$PROFILE_DIR/demo-prompt.txt"

cat <<EOF
Isolated Pi demo profile prepared.

In this terminal, start Pi with the isolated settings:
  PI_CODING_AGENT_DIR="$AGENT_DIR" pi

Use this fictional prompt when Pi starts:
  $(tr '\n' ' ' < "$PROFILE_DIR/demo-prompt.txt")

Then press Control-G. When finished, remove only this temporary profile:
  rm -rf "$PROFILE_DIR"

The profile contains no credentials. Configure a demo provider for this profile
beforehand if Pi needs one; never show a credential or settings screen in the capture.
EOF
