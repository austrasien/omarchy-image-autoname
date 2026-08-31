# Auto-Name Omarchy Screenshots

A **user-space companion** for [Omarchy](https://omarchy.org/) that turns generic captures into readable filenames — using the **focused window** plus a **local vision model**. No patch to `/usr/share/omarchy`.

> **⚡ Built for Hyprland Print:** snapshots the window *when you hit Print*, then Omarchy saves as usual. A watcher renames `screenshot-YYYY-MM-DD_HH-MM-SS.png` a moment later.

```
Brave - Page Discord - Channel discussion - 2026-01-15_09-30-00.png
Brave - Page GitHub - Pull request review - 2026-01-15_09-31-12.png
Kitty - git status - 2026-01-15_09-32-04.png
```

---

### ☕ Support the Project
If this saves you from a Pictures folder full of identical `screenshot-*.png` names, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

### 💬 Feedback & Community
Got a question, found a bug, or have a suggestion? Open an [**issue**](https://github.com/austrasien/omarchy-image-autoname/issues).

---

## 🚀 Overview

Omarchy already takes excellent screenshots. This project only names them. Print still goes through the real `omarchy-capture-screenshot`; we wrap it, remember which window was focused, and rename the file afterwards.

**Why bother?**

| | Without ❌ | With image-autoname ✅ |
| :--- | :--- | :--- |
| **Filename** | `screenshot-2026-01-15_09-30-00.png` | `Brave - Page Discord - Channel discussion - …` |
| **Context** | Date only | App, site (from the PWA/window class), and what is on screen |
| **Privacy** | — | Local Ollama by default; cloud Gemini is opt-in |
| **Your files** | — | Only *generic* names are touched (`screenshot-*`, `IMG_1234`, …) |

> **Note:** This is **not** an Omarchy shell plugin. `omarchy plugin add` installs QML into `omarchy-shell` and never runs an installer, so it cannot rebind Print, start a watcher, or pull a vision model.

## ✨ Key Features

### 🪟 Window context at Print time
- Records title, class, and PWA host (`brave-github.com…` → **GitHub**) *before* the screenshot tool runs.
- Native apps skip the `Page {Site}` segment: `Kitty - git status - …`.
- A Brave *profile* name (no domain in the class) is never treated as a website.

### 🔍 Local vision, then a sensible fallback
- Asks [Ollama](https://ollama.com/) (`qwen2.5vl:3b` by default) what is happening **in the rest of the capture**.
- Discards vague labels (`web page`, `site web`, `application web`) and falls back to the tab title.
- Optional Tesseract OCR, then optional Gemini if `GEMINI_API_KEY` is set.

### 🛡 Conservative by default
- Leaves `logo-acme.png` and anything you already named alone.
- Keeps the original `screenshot-*.png` path as a symlink for a few minutes so Omarchy’s **Edit** notification still opens.
- Window hints live in `$XDG_RUNTIME_DIR` (tmpfs), not next to the pictures.

### 🌍 Filename language
- 🇬🇧 **English** (default) — `LANGUAGE=en`
- 🇫🇷 **French** — `LANGUAGE=fr`

## 🛠 Installation (Omarchy)

1. **Install packages** (in a terminal):

   ```sh
   omarchy pkg add jq inotify-tools imagemagick ollama tesseract tesseract-data-eng tesseract-data-fra
   ```

2. **Clone and install:**

   ```sh
   git clone https://github.com/austrasien/omarchy-image-autoname.git
   cd omarchy-image-autoname
   ./install.sh --pull-model
   ```

3. **Reload Hyprland** so Print is rebound:

   ```sh
   hyprctl reload
   ```

4. **Start the watcher** (or log out and back in):

   ```sh
   ~/.config/omarchy/image-autoname/watch.sh &
   ```

`install.sh` copies scripts to `~/.config/omarchy/image-autoname/`, puts wrappers in `~/.local/bin`, and appends marked snippets to `~/.config/hypr/autostart.lua` and `bindings.lua` if they are missing. It **never** overwrites an existing `image-autoname.conf`.

Remove with `./uninstall.sh`. Renamed pictures and your config file are kept.

### Manual rename

```sh
image-autoname --force ~/Pictures/some-generic-name.png
```

## ⚙️ Configuration

`~/.config/omarchy/image-autoname.conf` — see [`config/image-autoname.conf.example`](config/image-autoname.conf.example).

| Variable | Meaning |
| :--- | :--- |
| `WATCH_DIRS` | Directories to watch (`Pictures` and `Downloads` by default) |
| `BACKEND` | `auto` (default), `ollama`, `gemini`, or `ocr` |
| `LANGUAGE` | `en` (default) or `fr` |
| `OLLAMA_MODEL` | Default `qwen2.5vl:3b` |
| `SYMLINK_SECONDS` | How long the original screenshot path stays as a symlink |

French filenames:

```sh
LANGUAGE=fr
```

Gemini, if enabled, receives a **resized** copy of the image. Leave `GEMINI_API_KEY` unset unless that is acceptable.

## ⚖️ License

Licensed under the **MIT License**. Permissive for both personal and commercial use, provided attribution is maintained.

---
*Developed to give Omarchy screenshots names you can actually search for — without sending your desktop to the cloud.*
