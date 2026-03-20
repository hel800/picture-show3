# picture-show3

A full-screen photo slideshow viewer built with **Python + PySide6 + QML**.
Hardware-accelerated transitions · Smartphone remote · Panorama mode · Star-Rating Filter

---

## Features

| | |
|---|---|
| **Transitions** | Fade, Slide, Zoom, Fade-to-black — GPU-accelerated via Qt Quick |
| **Sort** | By filename, by EXIF date taken, or random |
| **Loop** | Optional looping after the last photo |
| **Autoplay** | Configurable interval (1–30 s), timer restarts on manual navigation |
| **HUD** | Toggleable info bar: index, filename, IPTC caption, XMP star rating, EXIF date taken |
| **Star filter** | Filter the playlist to images at or above a minimum XMP star rating (1–5) |
| **Jump to image** | Instantly jump to any image by number with a live preview |
| **Panorama mode** | Auto-detects wide images and scrolls them smoothly across the screen |
| **Phone remote** | Scan the QR code or open the URL on any phone on the same Wi-Fi |
| **Keyboard** | Full keyboard control on both the settings screen and during the show |
| **Help overlay** | Press `?` at any time to see all keyboard shortcuts |
| **Cursor** | Completely hidden during the show (fullscreen and windowed) |

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

### Settings screen

| Key | Action |
|-----|--------|
| `Enter` | Start / resume picture show |
| `T` | Cycle transition style |
| `S` | Cycle sort order |
| `L` | Toggle loop |
| `A` | Toggle autoplay |
| `B` | Open folder browser |
| `H` | Open recent folders list |
| `R` | Cycle star rating filter |
| `V` | Open advanced settings |
| `F` | Toggle fullscreen |
| `?` | Help overlay |
| `Esc` | Quit dialog |

### During the picture show

| Key | Action |
|-----|--------|
| `→` / `←` | Next / previous photo |
| `Space` | Play / pause autoplay |
| `F` | Toggle fullscreen |
| `I` | Toggle HUD info bar |
| `J` | Jump to image by number |
| `P` | Panorama mode (wide images only) |
| `?` | Help overlay |
| `Esc` | Return to settings |

---

## Panorama mode

Press `P` during the show when viewing a wide image (aspect ratio ≥ 1.3× the window aspect ratio).
The image zooms to fill the window height and then scrolls left↔right continuously at a smooth pace.

- `P` or `Esc` — stop panorama and return to normal view
- `←` / `→` — stop panorama and navigate to the adjacent image
- Autoplay is paused while panorama is active and resumes when it stops
- Fullscreen toggle and the HUD work normally during panorama

---

## Smartphone remote

The remote is available as soon as the app launches — scan the QR code or open the URL
(e.g. `http://192.168.1.42:8765`) in any browser on the same Wi-Fi.
The remote buttons are disabled until the picture show is started, then activate automatically.

- ◀ Previous · ▶ Next · Play/Pause
- Live status (current photo, total, playing state)

---

## Star rating filter

picture-show3 reads the **XMP `Rating`** field (0–5 stars) embedded in JPEG and other supported files.
Use `R` on the settings screen to set a minimum rating; only images at or above that rating are shown.
Rating `0` = no filter (all images).

The current image's rating is also shown in the HUD info bar during the show.

---

## Advanced settings

Reachable via the **Advanced settings ›** link or by pressing `V` on the settings screen:

- **Transition duration** — how long each transition animation takes (100–3000 ms)
- **HUD size** — scales the info bar and its font (50–200 %)

---

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

EXIF orientation is applied automatically.
EXIF `DateTimeOriginal` is read for date-based sorting and HUD display.
IPTC `Caption/Abstract` (tag 2:120) is shown in the HUD when available.

---

## Building a standalone Windows executable

QML and image files are compiled into the binary so the source is not exposed in the distribution.

```bash
# 1. Install build dependencies (one-time)
pip install -r install/windows/requirements-build.txt

# 2. Generate the app icon (one-time, or when icon.svg changes)
python install/windows/make_icon.py

# 3. Compile QML + images into a Qt resource bundle
#    Re-run whenever any .qml or img/*.svg file changes
python install/windows/compile_resources.py

# 4. Build the executable
pyinstaller install/windows/picture-show3.spec ^
    --distpath install/windows/dist --workpath install/windows/build
```

Output: `install\windows\dist\picture-show3\picture-show3.exe` (onedir bundle, runs without Python installed).

To build the installer (requires [Inno Setup 6](https://jrsoftware.org/isdl.php)):

```bash
iscc install\windows\picture-show3.iss
```

Installer output: `install\windows\dist\installer\picture-show3-setup-0.5-beta.exe`

### Dev vs. frozen mode

When running from source (`python main.py`), QML files are read directly from disk — edit a `.qml` file and rerun immediately, no compile step needed.

When running the built exe, QML and SVGs are loaded from the compiled resource bundle embedded in `resources_rc.py`. PyInstaller sets `sys.frozen = True`, and the app switches to `qrc:/` paths automatically.

---

## Version

Current version is defined in `main.py` (`APP_VERSION`) and shown on the settings screen.


---

## Disclaimer

This software was developed with the assistance of AI (Anthropic Claude Code).
Architecture, feature design, and final decisions were made by the author;
code was written in collaboration with Claude.
