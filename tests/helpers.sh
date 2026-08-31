#!/usr/bin/env bash
# Offline checks for naming helpers. No images, no network.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"

fail=0
check() {
  local got expected=$1
  shift
  got=$("$@" || true)
  if [[ $got != "$expected" ]]; then
    echo "FAIL: expected '$expected' got '$got' ($*)" >&2
    fail=1
  else
    echo "ok: $expected"
  fi
}

check GitHub pretty_site_from_class 'brave-github.com__-Default'
check WhatsApp pretty_site_from_class 'brave-web.whatsapp.com__-Default'
check Discord pretty_site_from_class 'brave-discord.com__-Default'
check "Google Chat" pretty_site_from_class 'brave-chat.google.com__u_1_app_home-Default'

site=$(pretty_site_from_class 'brave-personal' || true)
[[ -z $site ]] || { echo "FAIL: profile class should not be a site ($site)" >&2; fail=1; }
echo "ok: profile class ignored"

check GitHub resolve_site 'brave-github.com__-Default' 'GitHub' 'github.com_/'
check Google resolve_site 'brave-browser' 'pasta recipe - Google Search - Brave' ''
check Discord resolve_site 'firefox' 'General | my-server | Discord' ''

check "Open pull request" detail_from_tab_title 'Open pull request | GitHub - Brave' 'GitHub'
check general detail_from_tab_title 'general | my-server | Discord - Brave' 'Discord'
check "Quarterly report draft" detail_from_tab_title 'Application | Quarterly report draft - Brave' ''

is_vague_description "web page of a website" && echo "ok: vague en" || { echo "FAIL: vague en" >&2; fail=1; }
is_vague_description "Page web d'un site web" && echo "ok: vague fr" || { echo "FAIL: vague fr" >&2; fail=1; }
is_vague_description "Channel discussion" && { echo "FAIL: specific marked vague" >&2; fail=1; } || echo "ok: specific"

is_junk_title "Edit workout" && { echo "FAIL: Edit workout marked junk" >&2; fail=1; } || echo "ok: edit workout"
is_junk_title "File Edit View Help" && echo "ok: menu junk" || { echo "FAIL: menu not junk" >&2; fail=1; }

is_generic_image_name "screenshot-2026-01-15_09-30-00.png" && echo "ok: generic screenshot" || { echo "FAIL: screenshot" >&2; fail=1; }
is_generic_image_name "logo-acme.png" && { echo "FAIL: logo treated generic" >&2; fail=1; } || echo "ok: keep logo-acme"

clean=$(clean_window_title "Inbox | Messages - Brave Work")
[[ $clean == "Inbox | Messages" ]] || { echo "FAIL: clean_window_title '$clean'" >&2; fail=1; }
echo "ok: strip Brave profile suffix"

if ((fail)); then
  echo "Some checks failed" >&2
  exit 1
fi
echo "All checks passed"
