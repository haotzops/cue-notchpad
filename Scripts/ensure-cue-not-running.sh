#!/bin/bash
set -euo pipefail

PGREP_COMMAND="${CUE_PGREP:-/usr/bin/pgrep}"
if "$PGREP_COMMAND" -x cue-host >/dev/null 2>&1; then
    printf 'Cue has an active edit session. Submit or cancel it before updating.\n' >&2
    exit 1
fi
