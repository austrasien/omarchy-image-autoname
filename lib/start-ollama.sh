#!/usr/bin/env bash
# Warm the NPU vision/chat runtime (Lemonade / FastFlowLM) at session start.
# Ollama is a fallback only, started on demand by autoname / llm_see.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname.conf"
[[ -f $CONF ]] && source "$CONF"

ensure_lemonade_server
exit $?
