#!/usr/bin/env bash
# Watch Pictures/Downloads and auto-name new generic-named images.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
AUTONAME="$SCRIPT_DIR/autoname.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname.conf"

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"$LOCK_DIR/image-autoname-watch.lock"
if ! flock -n 9; then
  echo "image-autoname-watch already running"
  exit 0
fi

WATCH_DIRS=("$HOME/Pictures" "$HOME/Downloads")
[[ -f $CONF ]] && source "$CONF"

if ((${#WATCH_DIRS[@]} == 0)); then
  echo "No WATCH_DIRS configured" >&2
  exit 1
fi

existing=()
for d in "${WATCH_DIRS[@]}"; do
  if [[ -d $d ]]; then
    existing+=("$d")
  else
    echo "Skip missing directory: $d" >&2
  fi
done
((${#existing[@]} > 0)) || { echo "No watch directories exist" >&2; exit 1; }

mkdir -p "$HINT_DIR"
echo "Watching: ${existing[*]}"

is_image_name() {
  local base=${1,,}
  [[ $base == *.png || $base == *.jpg || $base == *.jpeg || $base == *.webp || $base == *.gif || $base == *.avif || $base == *.bmp || $base == *.tif || $base == *.tiff ]]
}

should_skip() {
  local path=$1 base
  [[ -L $path ]] && return 0
  base=$(basename "$path")
  case "$base" in
    .* | *.part | *.crdownload | *.tmp | *.download | *.ytdl) return 0 ;;
  esac
  [[ $base == *~ ]] && return 0
  is_image_name "$base" || return 0
  is_already_autonamed "$base" && return 0
  is_generic_image_name "$base" || return 0
  return 1
}

LOCK="${XDG_RUNTIME_DIR:-/tmp}/image-autoname.lock"

process_one() {
  local path=$1 hint
  [[ -n $path && -f $path && ! -L $path ]] || return 0
  should_skip "$path" && return 0
  echo "$(date +'%H:%M:%S') new image: $path"
  mkdir -p "$HINT_DIR"
  hint="$HINT_DIR/$(basename "$path").json"
  if [[ ! -f $hint ]]; then
    snapshot_window "$hint"
  fi
  IMAGE_AUTONAME_WATCH=1 IMAGE_AUTONAME_HINT=$hint \
    timeout --signal=TERM --kill-after=8 75 \
    flock "$LOCK" nice -n 10 "$AUTONAME" "$path" \
    || { abort_ollama_runner; echo "autoname failed: $path" >&2; }
}

sweep_pending() {
  local dir f
  shopt -s nullglob
  for dir in "${existing[@]}"; do
    for f in "$dir"/screenshot-*.png; do
      process_one "$f"
    done
  done
}

# Catch files whose inotify event was lost while Ollama was stuck.
(
  exec 9>&-
  while true; do
    sleep 12
    sweep_pending
  done
) &

# Close the lock fd so inotifywait cannot inherit it and pin the lock after we die.
inotifywait -m -r \
  -e close_write,moved_to \
  --exclude '/\.' \
  --format '%w%f' \
  "${existing[@]}" 9>&- |
  while IFS= read -r path; do
    process_one "$path"
  done
