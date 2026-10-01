#!/usr/bin/env bash
# Install image-autoname into the current user's Omarchy/Hyprland session.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
CONF="$CONF_DIR/image-autoname.conf"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MARKER_START="-- image-autoname:start"
MARKER_END="-- image-autoname:end"
PULL_MODEL=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--pull-model]

Copies the scripts into ~/.config/omarchy/image-autoname/, installs wrappers
in ~/.local/bin, and appends Hyprland autostart + Print-key snippets if they
are not already present. Does not overwrite an existing config file.

  --pull-model   Also run: ollama pull qwen2.5vl:3b
EOF
  exit 2
}

for arg in "$@"; do
  case "$arg" in
    --pull-model) PULL_MODEL=1 ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

need() {
  command -v "$1" >/dev/null || MISSING+=("$1")
}

MISSING=()
need bash
need jq
need curl
need inotifywait
need magick
need flock
need timeout
need file
need realpath
need wl-copy

echo "Installing to $DEST"
mkdir -p "$DEST" "$BIN" "$CONF_DIR"
install -m 0755 "$ROOT/lib/"*.sh "$DEST/"

if [[ ! -f $CONF ]]; then
  install -m 0644 "$ROOT/config/image-autoname.conf.example" "$CONF"
  echo "Wrote $CONF"
else
  echo "Keeping existing $CONF"
fi

cat >"$BIN/image-autoname" <<EOF
#!/usr/bin/env bash
exec "$DEST/autoname.sh" "\$@"
EOF
cat >"$BIN/omarchy-capture-screenshot" <<EOF
#!/usr/bin/env bash
exec "$DEST/capture-screenshot.sh" "\$@"
EOF
chmod 0755 "$BIN/image-autoname" "$BIN/omarchy-capture-screenshot"
echo "Installed wrappers in $BIN"

append_marked() {
  local file=$1
  local body=$2
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || printf '' >"$file"
  if grep -qF "$MARKER_START" "$file" 2>/dev/null; then
    echo "Already configured: $file"
    return 0
  fi
  if grep -qF "image-autoname/" "$file" 2>/dev/null; then
    echo "Already references image-autoname (leaving as-is): $file"
    return 0
  fi
  {
    printf '\n%s\n' "$MARKER_START"
    printf '%s\n' "$body"
    printf '%s\n' "$MARKER_END"
  } >>"$file"
  echo "Updated $file"
}

append_marked "$HYPR/autostart.lua" "$(cat <<'LUA'
o.exec_on_start(os.getenv("HOME") .. "/.config/omarchy/image-autoname/start-ollama.sh")
o.exec_on_start(os.getenv("HOME") .. "/.config/omarchy/image-autoname/watch.sh")
LUA
)"

append_marked "$HYPR/bindings.lua" "$(cat <<'LUA'
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot", os.getenv("HOME") .. "/.config/omarchy/image-autoname/capture-screenshot.sh")
LUA
)"

echo
if ((${#MISSING[@]})); then
  echo "Missing commands: ${MISSING[*]}"
  echo "On Omarchy:  omarchy pkg add jq inotify-tools imagemagick wl-clipboard"
  echo "Optional:    omarchy pkg add ollama tesseract tesseract-data-eng tesseract-data-fra"
  echo "Optional:    Lemonade + FastFlowLM (https://github.com/lemonade-sdk/lemonade) for AMD NPU vision"
else
  echo "Required commands are present."
fi

if lemonade_api_base "${LEMONADE_HOST:-http://127.0.0.1:8000}" >/dev/null 2>&1; then
  echo "Lemonade is running; auto will prefer it over Ollama."
elif ! command -v ollama >/dev/null; then
  echo "Ollama is not installed. Local vision will be skipped until Ollama or Lemonade is available."
elif ((PULL_MODEL == 1)); then
  ollama pull "${OLLAMA_MODEL:-qwen2.5vl:3b}"
else
  echo "Vision model: ollama pull qwen2.5vl:3b   (or rerun ./install.sh --pull-model)"
  echo "Or start Lemonade with a vision model; auto prefers it when the server is up."
fi

echo
echo "Start (or restart) the watcher with:"
echo "  $DEST/watch.sh &"
echo "Print is rebound after the next Hyprland reload (hyprctl reload)."
echo "Uninstall with:  $ROOT/uninstall.sh"
