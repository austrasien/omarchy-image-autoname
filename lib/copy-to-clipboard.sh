#!/usr/bin/env bash
# Copy an image file onto the Wayland clipboard (pixels, not the path).
set -euo pipefail

file=${1:-}
[[ -n $file && -f $file ]] || exit 1

mime=$(file --brief --mime-type -- "$file" 2>/dev/null || true)
case "$mime" in
  image/*) ;;
  *) mime=image/png ;;
esac

exec wl-copy --type "$mime" <"$file"
