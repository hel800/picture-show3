# picture show 3

A full-screen photo picture show built with **PySide6 + QML**.
Hardware-accelerated transitions · Smartphone remote · No mouse interference.

---

## Features

| | |
|---|---|
| **Transitions** | Fade, Slide, Zoom, Fade-to-black — GPU-accelerated via Qt Quick |
| **Sort** | By filename, by EXIF date taken, or random |
| **Loop** | Optional looping after the last photo |
| **Autoplay** | Configurable interval (1–30 s) |
| **HUD** | Toggleable info bar: index, filename, date taken, play state |
| **Keyboard** | ← → navigate · Space play/pause · F fullscreen · I HUD · Esc exit |
| **Cursor** | Completely hidden during the show |
| **Phone remote** | Scan the QR code or open the URL on any phone on the same Wi-Fi |

---

## Requirements

- Python ≥ 3.14
- PySide6 ≥ 6.7
- Pillow ≥ 10.0
- qrcode[pil] ≥ 7.4

---

## Setup

```bash
# 1. Create a virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run
python main.py
```

Settings are saved as a human-readable INI file at `%APPDATA%\picture-show3\picture-show3.ini` (Windows).

---

## Keyboard shortcuts

### During the picture show

| Key | Action |
|-----|--------|
| `→` | Next photo |
| `←` | Previous photo |
| `Space` | Play / Pause autoplay |
| `F` | Toggle fullscreen |
| `I` | Toggle HUD info bar |
| `Esc` | Return to settings |

### On the settings screen

| Key | Action |
|-----|--------|
| `Enter` | Start / Resume picture show |
| `T` | Cycle transition style |
| `S` | Cycle sort order |
| `L` | Toggle loop |
| `A` | Toggle autoplay |
| `B` | Open folder browser |
| `H` | Open recent folders |
| `F` | Toggle fullscreen |
| `Esc` | Quit dialog |

---

## Smartphone remote

The remote is available as soon as the app launches — scan the QR code or open the URL (e.g. `http://192.168.1.42:8765`) in any browser on the same Wi-Fi.
The remote buttons are disabled until the picture show is started, then activate automatically.

- ◀ Previous · ▶ Next · Play/Pause
- Live status (current photo, total, playing state)

---

## Advanced settings

Reachable via the **Advanced settings ›** link on the settings screen:

- **Transition duration** — how long each transition animation takes (100–3000 ms)
- **HUD size** — scales the info bar and its font (50–200 %)

---

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

EXIF orientation is applied automatically.

---

## Building a standalone Windows executable

QML and image files are compiled into the binary so they are not readable as plain text in the distribution.

```bash
# 1. Install build dependencies (one-time)
pip install -r install/requirements-build.txt

# 2. Generate the app icon (one-time, or when icon.svg changes)
python install/make_icon.py

# 3. Compile QML + images into a Qt resource bundle (re-run whenever any .qml or img/*.svg changes)
python install/compile_resources.py

# 4. Build the executable
pyinstaller install/picture-show3.spec
```

Output: `dist\picture-show3\picture-show3.exe` (onedir bundle, runs without Python installed).

### Dev vs. frozen mode

When running from source (`python main.py`), QML files are read directly from disk — edit a `.qml` file and rerun to see the change immediately, no compile step needed.

When running the built exe, QML and SVGs are loaded from the compiled resource bundle embedded in `resources_rc.py`. PyInstaller detects `sys.frozen = True` (which it injects automatically), and the app switches to the `qrc:/` paths.

---

## Version

Current version is defined in `main.py` (`APP_VERSION`). The version is displayed subtly on the settings screen.
