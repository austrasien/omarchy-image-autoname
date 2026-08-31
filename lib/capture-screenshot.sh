#!/usr/bin/env bash
# Record the focused window at Print time, then take the usual Omarchy screenshot.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

REAL=/usr/share/omarchy/bin/omarchy-capture-screenshot
[[ -x $REAL ]] || { echo "Missing $REAL" >&2; exit 1; }

mkdir -p "$STATE_DIR" "$HINT_DIR"
hint_pre="$STATE_DIR/last-window.json"
snapshot_window "$hint_pre"

path=""
status=0
path=$("$REAL" "$@") || status=$?
[[ -n $path ]] && printf '%s\n' "$path"

if [[ $status -eq 0 && -n $path && -f $path ]]; then
  cp -- "$hint_pre" "$HINT_DIR/$(basename "$path").json"
fi
exit "$status"
