#!/usr/bin/env bash
# Shared helpers for screenshot auto-naming.

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/image-autoname"
HINT_DIR="$STATE_DIR/by-file"

abort_ollama_runner() {
  local pid
  pid=$(pgrep -x ollama | head -n1) || return 0
  pkill -P "$pid" -f '/usr/lib/ollama/llama-server' 2>/dev/null || true
}

snapshot_window() {
  local dest=${1:?}
  mkdir -p "$(dirname "$dest")"
  local title="" class="" initial_title="" initial_class=""
  if command -v hyprctl >/dev/null && command -v jq >/dev/null; then
    local json
    json=$(hyprctl activewindow -j 2>/dev/null || true)
    if [[ -n $json && $json != null ]]; then
      title=$(jq -r '.title // empty' <<<"$json")
      class=$(jq -r '.class // empty' <<<"$json")
      initial_title=$(jq -r '.initialTitle // empty' <<<"$json")
      initial_class=$(jq -r '.initialClass // empty' <<<"$json")
    fi
  fi
  jq -n \
    --arg title "${title:-}" \
    --arg class "${class:-}" \
    --arg initial_title "${initial_title:-}" \
    --arg initial_class "${initial_class:-}" \
    --argjson captured_at "$(date +%s)" \
    '{title:$title, class:$class, initial_title:$initial_title, initial_class:$initial_class, captured_at:$captured_at}' >"$dest"
}

pretty_app_name() {
  local class=${1:-} title=${2:-}
  local raw=${class,,}
  case "$raw" in
    grok-bot | grok | grok-bot*) printf '%s' "Grok Bot"; return ;;
    brave-browser | brave | brave-* | brave_*) printf '%s' "Brave"; return ;;
    google-chrome* | chromium* | chrome*) printf '%s' "Chrome"; return ;;
    firefox*) printf '%s' "Firefox"; return ;;
    zen | zen-browser | zen-*) printf '%s' "Zen"; return ;;
    nautilus | org.gnome.nautilus) printf '%s' "Files"; return ;;
    kitty) printf '%s' "Kitty"; return ;;
    alacritty) printf '%s' "Alacritty"; return ;;
    com.mitchellh.ghostty | ghostty) printf '%s' "Ghostty"; return ;;
    foot) printf '%s' "Foot"; return ;;
    code | code-oss | code-url-handler) printf '%s' "VS Code"; return ;;
    cursor | cursor-*) printf '%s' "Cursor"; return ;;
  esac
  local key=${raw##*.}
  key=${key%%:*}
  if [[ -n $key && $key != "$raw" ]]; then
    printf '%s' "$key" | tr '-_.' '   ' | awk '{
      for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)
      print
    }'
    return
  fi
  if [[ -n $raw ]]; then
    printf '%s' "$raw" | tr '-_.' '   ' | awk '{
      for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)
      print
    }'
    return
  fi
  if [[ -n $title ]]; then
    local words
    words=$(printf '%s' "$title" | wc -w)
    if ((words <= 4)); then
      printf '%s' "$title"
      return
    fi
  fi
  printf ''
}

clean_window_title() {
  local t=${1:-}
  t=$(printf '%s' "$t" | tr -d '\r')
  t=${t%%$'\n'*}
  t=$(printf '%s' "$t" | sed -E \
    -e 's/ — (Mozilla Firefox|Firefox|Brave|Chromium|Google Chrome|Chrome|Zen Browser|Vivaldi|Microsoft Edge|GNOME Web|Epiphany)$//' \
    -e 's/ - (Mozilla Firefox|Firefox|Chromium|Google Chrome|Chrome|Zen Browser|Vivaldi|Microsoft Edge)$//' \
    -e 's/ [-—] Brave( [[:alnum:]._-]+)?$//' \
    -e 's/ — (Files|Nautilus|Dolphin|Thunar|Nemo|PCManFM)$//' \
    -e 's/ – (Files|Nautilus)$//' \
    -e 's/[[:space:]]+$//')
  printf '%s' "$t"
}

is_browser_class() {
  local k=${1,,}
  [[ $k == brave* || $k == *chrome* || $k == *chromium* || $k == firefox* || $k == zen* || $k == *vivaldi* ]]
}

pretty_site_from_host() {
  local h=${1,,}
  h=${h#www.}
  h=${h%%/*}
  [[ -z $h ]] && return 1
  case "$h" in
    *whatsapp*) printf '%s' "WhatsApp" ;;
    *discord*) printf '%s' "Discord" ;;
    news.google.* | *news.google.*) printf '%s' "Google News" ;;
    mail.google.* | *gmail*) printf '%s' "Gmail" ;;
    chat.google.* | messages.google.*) printf '%s' "Google Chat" ;;
    *youtube*) printf '%s' "YouTube" ;;
    *github*) printf '%s' "GitHub" ;;
    x.com | x.com.* | *.x.com | *twitter.com*) printf '%s' "X" ;;
    maps.google.* | *openstreetmap*) printf '%s' "Maps" ;;
    *linkedin*) printf '%s' "LinkedIn" ;;
    *reddit*) printf '%s' "Reddit" ;;
    *amazon.*) printf '%s' "Amazon" ;;
    *notion*) printf '%s' "Notion" ;;
    *chatgpt* | *openai.com*) printf '%s' "ChatGPT" ;;
    grok.com | *grok.x.com*) printf '%s' "Grok" ;;
    calendar.google.*) printf '%s' "Google Calendar" ;;
    drive.google.*) printf '%s' "Google Drive" ;;
    docs.google.*) printf '%s' "Google Docs" ;;
    google.com | google.* | *.google.com | *.google.*) printf '%s' "Google" ;;
    *)
      local name=${h%%.*}
      [[ -z $name || $name == com || $name == www || $name == org || $name == net ]] && return 1
      printf '%s' "$name" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'
      ;;
  esac
}

pretty_site_from_class() {
  local class=${1,,} rest
  case "$class" in
    brave-browser | brave | firefox | google-chrome | chromium | chrome) return 1 ;;
  esac
  if [[ $class =~ ^brave-(.+) ]]; then
    rest="${BASH_REMATCH[1]}"
  elif [[ $class =~ ^(google-chrome|chromium|chrome)-(.+) ]]; then
    rest="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  rest=${rest%%__*}
  # A single token with no dot is a browser profile name, not a site host.
  [[ $rest == *.* ]] || return 1
  rest=${rest//_/.}
  pretty_site_from_host "$rest"
}

pretty_site_from_title() {
  local title=${1:-} host
  local lower
  lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *'recherche google'* | *'google search'*) printf '%s' "Google"; return 0 ;;
    *'google news'* | *'google actualités'*) printf '%s' "Google News"; return 0 ;;
    *gmail*) printf '%s' "Gmail"; return 0 ;;
    *discord*) printf '%s' "Discord"; return 0 ;;
    *whatsapp*) printf '%s' "WhatsApp"; return 0 ;;
    *youtube*) printf '%s' "YouTube"; return 0 ;;
  esac
  if [[ $lower =~ ([a-z0-9][-a-z0-9]*\.)+[a-z]{2,} ]]; then
    host="${BASH_REMATCH[0]}"
    pretty_site_from_host "$host" && return 0
  fi
  return 1
}

is_vague_description() {
  local t=${1:-} lower
  [[ -z $t ]] && return 0
  lower=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
  [[ $lower == *'page web'* || $lower == *'site web'* || $lower == *'application web'* ]] && return 0
  [[ $lower == *'web page'* || $lower == *'web app'* || $lower == *'website'* ]] && return 0
  [[ $lower == 'une page' || $lower == 'un site' || $lower == document ]] && return 0
  [[ $lower == 'a page' || $lower == 'a website' || $lower == 'a document' ]] && return 0
  [[ $lower == 'page d'\''accueil' || $lower == 'new tab' || $lower == 'nouvel onglet' ]] && return 0
  is_junk_title "$t"
}

pretty_site_from_initial_title() {
  local t=${1:-} host
  [[ -z $t ]] && return 1
  t=${t//_//}
  t=${t%% *}
  host=${t%%/*}
  pretty_site_from_host "$host"
}

resolve_site() {
  local class=${1:-} title=${2:-} initial_title=${3:-} site
  site=$(pretty_site_from_class "$class") && { printf '%s' "$site"; return 0; }
  site=$(pretty_site_from_initial_title "$initial_title") && { printf '%s' "$site"; return 0; }
  site=$(pretty_site_from_title "$title") && { printf '%s' "$site"; return 0; }
  return 1
}

detail_from_tab_title() {
  local t=${1:-} site=${2:-}
  t=$(clean_window_title "$t")
  [[ -z $t ]] && return 1
  t=$(printf '%s' "$t" | sed -E \
    -e 's/ - Recherche Google$//' \
    -e 's/ - Google Search$//' \
    -e 's/ - Google News$//' \
    -e 's/ - Google Actualités$//' \
    -e 's/ - YouTube$//' \
    -e 's/ \| Discord$//' \
    -e 's/ - Discord$//')
  if [[ -n $site ]]; then
    t=$(printf '%s' "$t" | sed -E "s/ [|-] ${site}\$//I")
  fi
  if [[ $t == *'|'* ]]; then
    t=$(printf '%s' "$t" | awk -F'|' -v site="$(printf '%s' "$site" | tr '[:upper:]' '[:lower:]')" '
      BEGIN {
        g["application"]=1; g["home"]=1; g["inbox"]=1; g["messages"]=1
        g["chat"]=1; g["settings"]=1; g["profile"]=1; g["dashboard"]=1
        g["search"]=1; g["accueil"]=1; g["new tab"]=1
      }
      {
        first = ""; longest = ""; longestl = 0
        for (i = 1; i <= NF; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
          low = tolower($i)
          if ($i == "" || low == site) continue
          if (length($i) > longestl) { longest = $i; longestl = length($i) }
          if (first == "" && !(low in g)) first = $i
        }
        if (first != "") print first
        else print longest
      }
    ')
  fi
  t=$(printf '%s' "$t" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
  [[ -z $t ]] && return 1
  if [[ -n $site ]]; then
    local lower site_l
    lower=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
    site_l=$(printf '%s' "$site" | tr '[:upper:]' '[:lower:]')
    [[ $lower == "$site_l" ]] && return 1
  fi
  is_junk_title "$t" && return 1
  is_vague_description "$t" && return 1
  printf '%s' "$t"
}

is_generic_image_name() {
  local base=${1##*/}
  local name=${base%.*}
  local lower re
  lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  re='^screenshot-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$'
  [[ $lower =~ $re ]] && return 0
  re='^screenshot([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0
  re='^screen[ -]?shot([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0
  re='^captura([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0
  [[ $lower == capture*cran* || $lower == capture*ecran* || $lower == capture*écran* ]] && return 0

  re='^image([[:space:]]*\([0-9]+\))?$'
  [[ $lower =~ $re ]] && return 0
  re='^image[_-][0-9]+$'
  [[ $lower =~ $re ]] && return 0
  [[ $lower == img ]] && return 0
  re='^img[_-]?[0-9]+'
  [[ $lower =~ $re ]] && return 0
  re='^dsc[_-]?[0-9]+'
  [[ $lower =~ $re ]] && return 0
  re='^pxl[_-]'
  [[ $lower =~ $re ]] && return 0
  re='^photo[_-]?[0-9]+'
  [[ $lower =~ $re ]] && return 0
  re='^fullsizerender([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0

  re='^(untitled|sans[[:space:]_-]*titre)([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0
  re='^(download|telechargement)([ _-].*)?$'
  [[ $lower =~ $re ]] && return 0
  [[ $lower == téléchargement || $lower == téléchargement* ]] && return 0
  re='^(copy|copie)[[:space:]_-]+(of|de)[[:space:]_-]'
  [[ $lower =~ $re ]] && return 0
  re='^(whatsapp|signal|telegram)[[:space:]_-].*(image|photo|video)'
  [[ $lower =~ $re ]] && return 0

  re='^[0-9]{5,}$'
  [[ $lower =~ $re ]] && return 0
  re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  [[ $lower =~ $re ]] && return 0

  return 1
}

is_already_autonamed() {
  local base=${1##*/}
  local name=${base%.*}
  local re=' - [0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9]+)?$'
  [[ $name =~ $re ]]
}

is_junk_title() {
  local t=${1:-}
  [[ -z $t ]] && return 0
  local lower
  lower=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
  [[ $t == *'File Edit View'* ]] && return 0
  [[ $t == *'Fichier'*'Affichage'* ]] && return 0
  [[ $t == *[Ff]enêtre*[Aa]pplication* || $t == *[Ff]enetre*[Aa]pplication* ]] && return 0
  [[ $t == ©* || $t == ®* || $t == +* ]] && return 0
  [[ $t == *' - -'* || $t == *'- -'* ]] && return 0
  local only_menu=1 word
  for word in $lower; do
    case "$word" in
      file|edit|view|help|fichier|edition|édition|affichage|aide) ;;
      *) only_menu=0; break ;;
    esac
  done
  ((only_menu == 1)) && return 0
  return 1
}

# Lemonade (AMD local server) speaks OpenAI at /api/v1 or /v1.
lemonade_api_base() {
  local host=${1:-http://127.0.0.1:8000}
  host=${host%/}
  local p
  for p in api/v1 v1; do
    if curl -sf --max-time 1 "$host/$p/models" >/dev/null; then
      printf '%s' "$host/$p"
      return 0
    fi
  done
  return 1
}

# stdin: OpenAI-style models list JSON. $1 = optional preferred model id.
# Prefers FastFlowLM (recipe flm / *-FLM) so Ryzen AI NPU is used when available.
lemonade_pick_vision_model() {
  local preferred=${1:-} json id
  json=$(cat)
  [[ -n $json ]] || return 1
  if [[ -n $preferred ]]; then
    id=$(jq -r --arg m "$preferred" '
      .data[]? | select(.id == $m or (.id | startswith($m))) | .id
    ' <<<"$json" | awk 'NF { print; exit }')
    [[ -n $id ]] || return 1
    printf '%s' "$id"
    return 0
  fi
  id=$(jq -r '
    [
      .data[]?
      | select(
          ((.labels // []) | index("vision"))
          or ((.id // "") | test("FLM|(?i)(-VL|VL-|vision)"))
        )
      | select((.labels // []) | index("image") | not)
    ]
    | sort_by(
        if .recipe == "flm" then 0
        elif ((.id // "") | test("(?i)-FLM")) then 1
        elif .recipe == "ryzenai-llm" then 2
        else 3 end
      )
    | .[0].id // empty
  ' <<<"$json")
  [[ -n $id && $id != null ]] || return 1
  printf '%s' "$id"
}
