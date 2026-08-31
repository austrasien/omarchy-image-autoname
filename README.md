# image-autoname

Rename new Omarchy screenshots (and generic downloads) from the focused window plus a **local** vision model.

```
Brave - Page Discord - Channel discussion - 2026-01-15_09-30-00.png
Brave - Page GitHub - Pull request review - 2026-01-15_09-31-12.png
Kitty - git status - 2026-01-15_09-32-04.png
```

It does not patch `/usr/share/omarchy`. Screenshots are still taken by Omarchy; this project wraps Print, remembers the focused window, and renames the file afterwards.

## How it works

1. **Print** runs `capture-screenshot.sh`, which snapshots the focused Hyprland window (title, class, PWA host), then calls the real `omarchy-capture-screenshot`.
2. Omarchy writes `~/Pictures/screenshot-YYYY-MM-DD_HH-MM-SS.png`.
3. **watch.sh** notices the file (and generic names in `~/Downloads`).
4. **autoname.sh** asks a local Ollama vision model what is happening in the rest of the image. The **site** comes from the window class / tab title (`brave-github.com…` → GitHub). Vague labels like “web page” are discarded in favour of the tab title.
5. The original `screenshot-*.png` path is kept as a symlink for a few minutes so Omarchy’s “Edit” notification still opens.

Native apps skip the `Page {Site}` segment.

Only **generic** names are renamed (`screenshot-*`, `image.png`, `IMG_1234`, `Capture d’écran`, …). A file you already named `logo-acme.png` is left alone.

## Requirements

- [Omarchy](https://omarchy.org/) (Hyprland)
- `jq`, `inotify-tools`, ImageMagick (`magick`), `curl`
- Optional, recommended: [Ollama](https://ollama.com/) and `qwen2.5vl:3b`
- Optional fallback: Tesseract (`tesseract-data-eng`, `tesseract-data-fra`)
- Optional cloud fallback: `GEMINI_API_KEY` (off by default)

On Omarchy:

```sh
omarchy pkg add jq inotify-tools imagemagick ollama tesseract tesseract-data-eng tesseract-data-fra
```

## Install

```sh
git clone https://github.com/austrasien/omarchy-image-autoname.git
cd omarchy-image-autoname
./install.sh --pull-model
hyprctl reload
```

`install.sh` copies the scripts to `~/.config/omarchy/image-autoname/`, puts wrappers in `~/.local/bin`, and appends marked snippets to `~/.config/hypr/autostart.lua` and `bindings.lua` if they are not already there. It never overwrites an existing `image-autoname.conf`.

Start the watcher now (or log out and back in):

```sh
~/.config/omarchy/image-autoname/watch.sh &
```

Remove with `./uninstall.sh`. Your renamed pictures and `image-autoname.conf` are kept.

## Configuration

`~/.config/omarchy/image-autoname.conf` — see `config/image-autoname.conf.example`.

| Variable | Meaning |
|---|---|
| `WATCH_DIRS` | Directories to watch |
| `BACKEND` | `auto` (default), `ollama`, `gemini`, or `ocr` |
| `LANGUAGE` | `en` (default) or `fr` for the vision prompt |
| `OLLAMA_MODEL` | Default `qwen2.5vl:3b` |
| `SYMLINK_SECONDS` | How long the original screenshot path stays as a symlink |

French filenames:

```sh
LANGUAGE=fr
```

## Privacy

- Vision is **local** (Ollama) unless you set `GEMINI_API_KEY`.
- Window hints live in `$XDG_RUNTIME_DIR` (tmpfs, gone at logout). They are not written next to the pictures.
- Gemini, if enabled, receives a **resized** copy of the image. Do not turn it on if that is unacceptable.
- The watcher never uploads files by itself.

This is not an Omarchy shell plugin. `omarchy plugin add` only installs QML into `omarchy-shell` and does not run installers, so a marketplace listing would not be able to install Ollama, rebind Print, or start the watcher.

## Manual rename

```sh
image-autoname --force ~/Pictures/some-generic-name.png
```

## License

MIT
