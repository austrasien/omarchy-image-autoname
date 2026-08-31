#!/usr/bin/env bash
# Remove wrappers and Hyprland snippets. Leaves renamed files and the config alone.
set -euo pipefail

DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MARKER_START="-- image-autoname:start"
MARKER_END="-- image-autoname:end"

remove_marked() {
  local file=$1
  [[ -f $file ]] || return 0
  if ! grep -qF "$MARKER_START" "$file"; then
    echo "No installer markers in $file (not touching it)"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip { next }
    { print }
  ' "$file" >"$tmp"
  mv -- "$tmp" "$file"
  echo "Removed snippet from $file"
}

echo "Stopping watcher if it is ours..."
pgrep -f "^bash $DEST/watch.sh$" >/dev/null && pkill -f "^bash $DEST/watch.sh$" || true

remove_marked "$HYPR/autostart.lua"
remove_marked "$HYPR/bindings.lua"

for wrapper in "$BIN/image-autoname" "$BIN/omarchy-capture-screenshot"; do
  if [[ -f $wrapper ]] && grep -q "$DEST/" "$wrapper" 2>/dev/null; then
    rm -f "$wrapper"
    echo "Removed $wrapper"
  fi
done

if [[ -d $DEST ]]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
fi

echo "Left in place: ~/.config/omarchy/image-autoname.conf (delete it yourself if you want)"
echo "Reload Hyprland to restore the default Print binding: hyprctl reload"
