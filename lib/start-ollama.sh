#!/usr/bin/env bash
# Start a local vision runtime. Prefer a running Lemonade server (FastFlowLM NPU
# or llama.cpp iGPU); otherwise start Ollama if it is not already up.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname.conf"
[[ -f $CONF ]] && source "$CONF"

LEMONADE_HOST="${LEMONADE_HOST:-http://127.0.0.1:8000}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

if lemonade_api_base "$LEMONADE_HOST" >/dev/null; then
  exit 0
fi

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
