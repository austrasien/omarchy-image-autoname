#!/usr/bin/env bash
# Rename one image from its contents.
# Example: "Brave - Page Discord - Channel discussion - 2026-01-15_09-30-00.png"
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/image-autoname.conf"
[[ -f $CONF ]] && source "$CONF"

BACKEND="${BACKEND:-auto}"
LANGUAGE="${LANGUAGE:-en}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5vl:3b}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
OCR_LANGS="${OCR_LANGS:-eng+fra}"
SYMLINK_SECONDS="${SYMLINK_SECONDS:-180}"

PROMPT_EN='You are naming a screenshot. Reply ONLY with what is happening in the rest of the image, excluding the browser and site name (3 to 8 words). Forbidden: web page, website, web app, document, the browser name, the site name. Examples: Channel discussion, Issue comments open, Search for pasta recipe, City map, Filled-in form. No quotes, no trailing punctuation, no extension, no date. Ignore File/Edit/View menus, copyright marks, clocks. English, except proper nouns.'

PROMPT_FR='Tu analyses une capture d'\''écran. Réponds UNIQUEMENT par ce qui se passe dans le reste de l'\''image, hors navigateur et hors site (3 à 8 mots). Interdit: page web, site web, application web, document, le nom du navigateur, le nom du site. Exemples: Discussion dans un salon, Commentaires d'\''une issue, Recherche recette pasta, Carte d'\''une ville, Formulaire rempli. Pas de guillemets, pas de ponctuation finale, pas d'\''extension, pas de date. Français, sauf noms propres. Ignore menus File/Edit/View, ©, horloges.'

if [[ ${LANGUAGE,,} == fr ]]; then
  PROMPT=$PROMPT_FR
else
  PROMPT=$PROMPT_EN
fi

usage() {
  echo "Usage: image-autoname [--force] <image>" >&2
  exit 2
}

FORCE=0
FILE=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) FILE=$arg ;;
  esac
done
[[ -n $FILE ]] || usage
[[ -e $FILE ]] || { echo "Not a file: $FILE" >&2; exit 1; }

if [[ -L $FILE ]]; then
  echo "Skip symlink: $FILE"
  exit 0
fi
[[ -f $FILE ]] || { echo "Not a file: $FILE" >&2; exit 1; }

FILE=$(realpath "$FILE")
BASE=$(basename "$FILE")
DIR=$(dirname "$FILE")
EXT=${BASE##*.}
EXT=${EXT,,}
ORIGINAL_BASE=$BASE

if ((FORCE == 0)) && is_already_autonamed "$BASE"; then
  echo "Already named, skip: $BASE"
  exit 0
fi

if ((FORCE == 0)) && [[ ${IMAGE_AUTONAME_WATCH:-} == 1 ]] && ! is_generic_image_name "$BASE"; then
  echo "Keep original name: $BASE"
  exit 0
fi

wait_stable() {
  local f=$1 prev=-1 s i missing=0
  for i in $(seq 1 24); do
    if [[ ! -f $f ]]; then
      missing=$((missing + 1))
      ((missing >= 4)) && return 1
      sleep 0.2
      continue
    fi
    missing=0
    s=$(stat -c '%s' "$f")
    if [[ $s -gt 256 && $s -eq $prev ]]; then
      sleep 0.1
      [[ $(stat -c '%s' "$f") -eq $prev ]] && return 0
    fi
    prev=$s
    sleep 0.2
  done
  [[ -f $f && $(stat -c '%s' "$f") -gt 256 ]]
}

wait_stable "$FILE" || { echo "File not stable: $FILE" >&2; exit 1; }

SIZE=$(stat -c '%s' "$FILE")
if [[ $SIZE -lt 256 || $SIZE -gt 52428800 ]]; then
  echo "Skip (size $SIZE): $BASE"
  exit 0
fi

MIME=$(file --brief --mime-type "$FILE")
[[ $MIME == image/* ]] || { echo "Not an image ($MIME): $BASE"; exit 0; }

log() { printf '%s %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }

load_window_hint() {
  local f=${IMAGE_AUTONAME_HINT:-$HINT_DIR/$BASE.json}
  [[ -f $f ]] || f="$STATE_DIR/last-window.json"
  [[ -f $f ]] || return 1
  WINDOW_RAW=$(jq -r '.title // empty' "$f" 2>/dev/null || true)
  WINDOW_CLASS=$(jq -r '.class // empty' "$f" 2>/dev/null || true)
  WINDOW_INITIAL=$(jq -r '.initial_title // empty' "$f" 2>/dev/null || true)
}

WINDOW_RAW=""
WINDOW_CLASS=""
WINDOW_INITIAL=""
load_window_hint || true
WINDOW_HINT=$(clean_window_title "$WINDOW_RAW")
SITE_NAME=$(resolve_site "$WINDOW_CLASS" "$WINDOW_RAW" "$WINDOW_INITIAL" || true)

sanitize_title() {
  local t=$1
  t=$(printf '%s' "$t" | tr -d '\r')
  t=${t%%$'\n'*}
  t=${t%%$'\r'*}
  t=${t#\"}
  t=${t%\"}
  t=${t#\'}
  t=${t%\'}
  t=$(printf '%s' "$t" | sed -E \
    -e 's/[©®™]//g' \
    -e 's/^[[:space:]]*(Title|Titre)[[:space:]]*:[[:space:]]*//I' \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T_ ]?[0-9]{2}[-:][0-9]{2}[-:][0-9]{2}//g' \
    -e 's/\b(Capture d['\''’]?écran|Capture|Screenshot|Screen ?shot)\b//Ig' \
    -e 's/[\/\\:*?"<>|+]+/ /g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^[+[:space:]._-]+//' \
    -e 's/[[:space:]._+-]+$//' \
    -e 's/ -+/ -/g')
  t=$(printf '%s' "$t" | awk '{
    out=""
    n=0
    for (i=1; i<=NF && n<8; i++) {
      if (length($i) < 2) continue
      if ($i ~ /^[ox]$/) continue
      out = (out ? out " " : "") $i
      n++
    }
    print out
  }')
  t=${t:0:80}
  t=${t%"${t##*[![:space:]]}"}
  printf '%s' "$t"
}

APP_NAME=$(pretty_app_name "$WINDOW_CLASS" "$WINDOW_RAW")
APP_NAME=$(sanitize_title "$APP_NAME")
SITE_NAME=$(sanitize_title "${SITE_NAME:-}")

build_prompt() {
  local prompt=$PROMPT
  if [[ ${LANGUAGE,,} == fr ]]; then
    if [[ -n ${APP_NAME:-} ]]; then
      prompt+=$'\n'"L'application est « $APP_NAME ». Ne répète pas ce nom."
    fi
    if [[ -n ${SITE_NAME:-} ]]; then
      prompt+=$'\n'"Le site ou le service est « $SITE_NAME ». Ne répète pas ce nom. Décris seulement ce qui se passe dans le reste de la capture (conversation, action, sujet, lieu)."
    else
      prompt+=$'\n'"Décris seulement le contenu visible, pas l'application."
    fi
    if [[ -n $WINDOW_HINT ]]; then
      prompt+=$'\n'"Titre de l'onglet (indice, à utiliser si le contenu correspond) : $WINDOW_HINT"
    fi
  else
    if [[ -n ${APP_NAME:-} ]]; then
      prompt+=$'\n'"The application is \"$APP_NAME\". Do not repeat that name."
    fi
    if [[ -n ${SITE_NAME:-} ]]; then
      prompt+=$'\n'"The site or service is \"$SITE_NAME\". Do not repeat that name. Describe only what is happening in the rest of the screenshot (conversation, action, subject, place)."
    else
      prompt+=$'\n'"Describe only the visible content, not the application."
    fi
    if [[ -n $WINDOW_HINT ]]; then
      prompt+=$'\n'"Tab title (hint, use it if it matches the content): $WINDOW_HINT"
    fi
  fi
  printf '%s' "$prompt"
}

describe_ollama() {
  curl -sf --max-time 1 "$OLLAMA_HOST/api/tags" >/dev/null || return 1
  curl -sf --max-time 1 "$OLLAMA_HOST/api/tags" \
    | jq -e --arg m "$OLLAMA_MODEL" '.models[]? | select(.name == $m or (.name | startswith($m)))' >/dev/null \
    || return 1

  local tmp prompt jsonf resp imgf
  tmp=$(mktemp --suffix=.jpg)
  magick "$FILE" -auto-orient -resize '768x768>' -strip -quality 75 "$tmp" || cp -- "$FILE" "$tmp"
  prompt=$(build_prompt)

  imgf=$(mktemp)
  jsonf=$(mktemp)
  base64 -w0 "$tmp" >"$imgf"
  rm -f "$tmp"
  jq -n \
    --arg model "$OLLAMA_MODEL" \
    --arg prompt "$prompt" \
    --rawfile img "$imgf" \
    '{model:$model, prompt:$prompt, images:[$img], stream:true, keep_alive:"5m", options:{temperature:0.1, num_predict:32, num_ctx:2048}}' \
    >"$jsonf"
  rm -f "$imgf"
  resp=$(curl -sS -N --max-time 45 "$OLLAMA_HOST/api/generate" \
    -H 'Content-Type: application/json' \
    --data-binary @"$jsonf") || {
    rm -f "$jsonf"
    abort_ollama_runner
    return 1
  }
  rm -f "$jsonf"
  printf '%s\n' "$resp" | grep -E '^{' | jq -r '.response // empty' | tr -d '\n'
  printf '\n'
}

gemini_key() {
  if [[ -n ${GEMINI_API_KEY:-} ]]; then
    printf '%s' "$GEMINI_API_KEY"
    return 0
  fi
  return 1
}

describe_gemini() {
  local key mime tmp imgf jsonf prompt resp
  key=$(gemini_key) || return 1
  tmp=$(mktemp --suffix=.jpg)
  magick "$FILE" -auto-orient -resize '1280x1280>' -strip -quality 80 "$tmp" || cp -- "$FILE" "$tmp"
  mime=$(file --brief --mime-type "$tmp")
  imgf=$(mktemp)
  jsonf=$(mktemp)
  base64 -w0 "$tmp" >"$imgf"
  rm -f "$tmp"
  prompt=$(build_prompt)
  jq -n --arg prompt "$prompt" --arg mime "$mime" --rawfile data "$imgf" '{
    contents: [{parts: [
      {text: $prompt},
      {inline_data: {mime_type: $mime, data: $data}}
    ]}],
    generationConfig: {temperature: 0.1, maxOutputTokens: 32}
  }' >"$jsonf"
  rm -f "$imgf"
  resp=$(curl -sf --max-time 45 \
    "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent" \
    -H "x-goog-api-key: $key" \
    -H "Content-Type: application/json" \
    --data-binary @"$jsonf") || { rm -f "$jsonf"; return 1; }
  rm -f "$jsonf"
  jq -r '.candidates[0].content.parts[0].text // empty' <<<"$resp"
}

describe_ocr() {
  command -v tesseract >/dev/null || return 1
  local tmp text langs=$OCR_LANGS
  tmp=$(mktemp --suffix=.png)
  magick "$FILE" -auto-orient -resize '1920x1920>' -colorspace Gray -contrast-stretch 2%x2% "$tmp" || cp -- "$FILE" "$tmp"
  tesseract --list-langs 2>/dev/null | grep -qx fra || langs=eng
  text=$(tesseract "$tmp" stdout -l "$langs" --psm 6 2>/dev/null || true)
  rm -f "$tmp"
  [[ -n $text ]] || return 1
  printf '%s\n' "$text" | awk '
    BEGIN { IGNORECASE=1 }
    {
      gsub(/^[ \t]+|[ \t]+$/, "")
      if (length($0) < 3 || length($0) > 60) next
      if ($0 ~ /https?:|www\.|cookie|accept|javascript|file edit view|fichier/ ) next
      if (n++ < 8) print
    }
  ' | awk 'NR==1 { print; exit }'
}

describe_image() {
  local title=""
  case "$BACKEND" in
    ollama) title=$(describe_ollama || true) ;;
    gemini) title=$(describe_gemini || true) ;;
    ocr) title=$(describe_ocr || true) ;;
    auto)
      title=$(describe_ollama || true)
      if [[ -z $title ]]; then
        log "Ollama unavailable, trying Gemini"
        title=$(describe_gemini || true)
      fi
      if [[ -z $title ]]; then
        log "Vision unavailable, trying OCR"
        title=$(describe_ocr || true)
      fi
      ;;
    *) echo "Unknown BACKEND=$BACKEND" >&2; return 1 ;;
  esac
  title=$(sanitize_title "$title")
  if is_vague_description "$title"; then
    title=""
  fi
  printf '%s' "$title"
}

TITLE=$(describe_image)

strip_known_names() {
  local desc=$1
  shift
  [[ -z $desc ]] && { printf ''; return; }
  local extra="" name
  for name in "$@"; do
    [[ -n $name ]] && extra+=" $name"
  done
  extra=$(printf '%s' "$extra" | sed -E 's/^[[:space:]]+//')
  local out
  out=$(printf '%s' "$desc" | awk -v names="$extra" '
    BEGIN {
      n = split(tolower(names), aw, /[[:space:]]+/)
    }
    {
      out = ""
      for (i = 1; i <= NF; i++) {
        skip = 0
        low = tolower($i)
        gsub(/[.,:;!?]/, "", low)
        if (low == "page" || low == "web" || low == "site") skip = 1
        for (j = 1; j <= n; j++) if (low == aw[j]) skip = 1
        if (skip) continue
        out = (out ? out " " : "") $i
      }
      print out
    }
  ')
  printf '%s' "$out"
}

if is_vague_description "$TITLE"; then
  TITLE=""
fi
if [[ -z $TITLE ]]; then
  TITLE=$(detail_from_tab_title "$WINDOW_HINT" "$SITE_NAME" || true)
  log "Vision vague, falling back to tab title: ${TITLE:-none}"
fi
TITLE=$(sanitize_title "$(strip_known_names "$TITLE" "$APP_NAME" "$SITE_NAME")")
if is_vague_description "$TITLE" || is_junk_title "$TITLE" || [[ -z $TITLE ]]; then
  TITLE=$(detail_from_tab_title "$WINDOW_HINT" "$SITE_NAME" || true)
  TITLE=$(sanitize_title "$(strip_known_names "$TITLE" "$APP_NAME" "$SITE_NAME")")
fi
if is_vague_description "$TITLE" || is_junk_title "$TITLE"; then
  TITLE=""
fi
if [[ -n $TITLE && -n $SITE_NAME ]]; then
  local_cmp=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]')
  site_cmp=$(printf '%s' "$SITE_NAME" | tr '[:upper:]' '[:lower:]')
  [[ $local_cmp == "$site_cmp" ]] && TITLE=""
fi

if [[ -z $TITLE && -z $APP_NAME ]]; then
  log "Could not name $BASE"
  exit 0
fi

TS=$(date -d "@$(stat -c '%Y' "$FILE")" +'%Y-%m-%d_%H-%M-%S')
STEM=""
if is_browser_class "$WINDOW_CLASS" && [[ -n $SITE_NAME && -n $TITLE ]]; then
  STEM="$APP_NAME - Page $SITE_NAME - $TITLE"
elif is_browser_class "$WINDOW_CLASS" && [[ -n $SITE_NAME ]]; then
  STEM="$APP_NAME - Page $SITE_NAME"
elif [[ -n $APP_NAME && -n $TITLE ]]; then
  STEM="$APP_NAME - $TITLE"
elif [[ -n $APP_NAME ]]; then
  STEM=$APP_NAME
else
  STEM=$TITLE
fi

DEST_BASE="$STEM - $TS.$EXT"
DEST="$DIR/$DEST_BASE"

if [[ $DEST == "$FILE" ]]; then
  log "Name unchanged: $BASE"
  exit 0
fi

n=2
while [[ -e $DEST || -L $DEST ]]; do
  DEST="$DIR/$STEM - $TS-$n.$EXT"
  DEST_BASE=$(basename "$DEST")
  n=$((n + 1))
done

mv -- "$FILE" "$DEST"
log "Renamed: $BASE → $DEST_BASE"

# Keep the original screenshot path alive so Omarchy's "Edit" notification still opens.
if [[ $ORIGINAL_BASE == screenshot-* ]]; then
  link="$DIR/$ORIGINAL_BASE"
  if [[ ! -e $link ]]; then
    ln -sfn "$DEST_BASE" "$link"
    (
      sleep "$SYMLINK_SECONDS"
      if [[ -L $link ]]; then
        rm -f "$link"
      fi
    ) &
    disown
  fi
fi

if command -v omarchy-notification-send >/dev/null; then
  omarchy-notification-send "Screenshot renamed" "$DEST_BASE" --image "$DEST" \
    --exec "${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}" "$DEST" -t 4000 || true
fi
