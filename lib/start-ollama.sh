#!/usr/bin/env bash
# Start a user-local Ollama daemon if the API is not already up.
set -uo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname.conf"
[[ -f $CONF ]] && source "$CONF"

OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

if curl -sf --max-time 1 "$OLLAMA_HOST/api/version" >/dev/null; then
  exit 0
fi

# Optional GPU hints from the config (safe to leave unset).
[[ -n ${OLLAMA_VULKAN:-} ]] && export OLLAMA_VULKAN
[[ -n ${OLLAMA_IGPU_ENABLE:-} ]] && export OLLAMA_IGPU_ENABLE
[[ -n ${GGML_VK_VISIBLE_DEVICES:-} ]] && export GGML_VK_VISIBLE_DEVICES

logdir="${XDG_STATE_HOME:-$HOME/.local/state}/image-autoname"
mkdir -p "$logdir"
exec nice -n 10 ollama serve >>"$logdir/ollama.log" 2>&1
