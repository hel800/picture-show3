# picture-show3

A full-screen photo slideshow viewer built with **Python + PySide6 + QML**.
Hardware-accelerated transitions · Smartphone remote · Panorama mode · Star-Rating Filter

---

## Features

| **Feature** | Description |
|---|---|
| **Transitions** | Fade, Slide, Zoom, Fade-to-black — GPU-accelerated via Qt Quick |
| **Sort** | By filename, by EXIF date taken, or random |
| **Loop** | Optional looping after the last photo |
| **Autoplay** | Configurable interval (1–30 s), timer restarts on manual navigation |
| **HUD** | Toggleable info bar: index, filename, IPTC caption, XMP star rating, EXIF date taken |
| **EXIF panel** | Press `,` during the show for a detailed EXIF overlay: camera, aperture, shutter, ISO, focal length, exposure program, flash, dimensions |
| **Star filter** | Filter the playlist to images at or above a minimum XMP star rating (1–5) |
| **Star rating editor** | Press `0`–`5` during the show to set the XMP star rating of the current image; `0` removes it. A confirmation popup with animated stars appears — `↵` to save, `Esc` to cancel |
| **Caption editor** | Press `C` during the show to edit the IPTC caption of the current image. A popup loads the existing caption into a text field — `↵` to save, `Esc` to cancel. Press `Tab Tab` (< 600 ms apart) to copy the previous image's caption |
| **Recursive folders** | Optional: include subfolders in the scan (toggle in settings) |
| **Background scanning** | Folder scanning and sorting run in background threads — UI stays responsive; Start button enables when ready |
| **Jump to image** | Instantly jump to any image by number with a live preview |
| **Panorama mode** | Auto-detects wide images and scrolls them smoothly across the screen |
| **Mouse navigation** | Optional left/right click to advance or go back (toggle in Advanced settings) |
| **Phone remote** | Scan the QR code or open the URL on any phone on the same Wi-Fi |
| **Keyboard** | Full keyboard control on both the settings screen and during the show |
| **Help overlay** | Press `F1` at any time to see all keyboard shortcuts |
| **Cursor** | Hidden in fullscreen; visible in windowed mode |
| **Multilingual** | UI language selectable in Advanced settings; `Auto` follows system locale |
| **Update check** | Checks GitHub Releases for a newer version on startup — opt-out in Advanced settings |
| **Jump-start mode** | `python main.py <folder>` — skips the settings page and launches the show immediately; Esc returns to settings |
| **Kiosk mode** | `python main.py --kiosk <folder>` — unattended display mode; Esc shows a quit confirmation dialog instead of going to settings |

---

## Requirements

- Python ≥ 3.14
- PySide6 ≥ 6.7
- Pillow ≥ 10.0
- pillow-heif ≥ 0.16 (HEIC/HEIF support)
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

# Jump-start: load a folder and go straight to the show (Esc returns to settings)
python main.py /path/to/photos

# Kiosk mode: unattended display, no settings UI (Esc shows quit dialog)
python main.py --kiosk /path/to/photos
```

---

## Running the tests

```bash
# Install test dependencies (one-time)
pip install -r tests/requirements-test.txt

# Run all tests
python -m pytest

# Run with verbose output
python -m pytest -v
```

244 tests across controller logic, HTTP endpoints, and image providers. Tests require no display and create all fixture images at runtime — no test assets are committed to the repo.

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
| `,` | Show / hide extended EXIF info panel |
| `J` | Jump to image by number |
| `0`–`5` | Set star rating (0 = remove); ↵ to confirm, Esc to cancel |
| `C` | Edit IPTC caption; ↵ to save, Esc to cancel; Tab Tab copies previous image's caption |
| `P` | Panorama mode (wide images only) |
| `?` | Help overlay |
| `Esc` | Return to settings |
| Left click | Next photo (when mouse navigation enabled) |
| Right click | Previous photo (when mouse navigation enabled) |
| Double-click | Toggle fullscreen |

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
Ratings can also be set or changed directly during the show with keys `0`–`5`.

---

## Advanced settings

Reachable via the **Advanced settings ›** link or by pressing `V` on the settings screen.
Settings are grouped into four tabs:

| Tab | Options |
|---|---|
| **General** | Transition duration (100–3000 ms) · UI language · Update check on startup |
| **Controls** | Mouse button navigation (left = next, right = previous) |
| **HUD** | HUD size (50–200 %) |
| **Remote** | Smartphone remote enable/disable · Port |

### Keyboard navigation inside Advanced settings

| Key | Action |
|-----|--------|
| `Tab` / `Shift+Tab` | Cycle tabs |
| `↑` / `↓` | Move between options; `↓` on last option focuses **Done** |
| `←` / `→` | Change the selected option's value |
| `Enter` | Edit a text field (Port) · Close dialog when Done is focused |
| `Esc` | Close dialog |

---

## Translations

The UI language is selected in **Advanced settings › LANGUAGE**.
`Auto` follows the system locale; a restart is required after changing the language.

The active language is stored as `language` in the settings INI file and can be set manually:

```ini
language = de     ; e.g. de, fr, auto
```

Two helper scripts live in `translations/`:

```bash
# Pull new strings from source, report unfinished per language
python translations/update.py

# Build .qm files for use in dev mode
python translations/compile.py
```

### Adding a new language

1. Run `python translations/update.py` to make sure all `.ts` files are current.
2. Create `translations/picture-show3_<code>.ts` (e.g. `picture-show3_es.ts` for Spanish)
   by copying an existing `.ts` file and clearing the `<translation>` values.
3. Open it in **Qt Linguist** (`pyside6-linguist`) or any text editor and fill in the `<translation>` elements.
4. Run `python translations/compile.py` to build the `.qm` file.
5. Restart the app — the new language appears automatically in the language selector.

Commit the `.ts` source file; `.qm` files are generated and excluded from git.

### Keeping translations up to date

After adding or changing `qsTr()`/`self.tr()` strings in the source:

```bash
python translations/update.py   # updates all .ts files, lists what still needs translating
python translations/compile.py  # rebuilds .qm files
```

The build script (`install/windows/compile_resources.py`) runs `pyside6-lrelease` automatically as part of the build.

---

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

HEIC/HEIF files require the `pillow-heif` package (included in `requirements.txt`).
AVIF support requires Pillow ≥ 9.1 (satisfied by the `≥ 10.0` constraint).

EXIF orientation is applied automatically.
EXIF `DateTimeOriginal` is read for date-based sorting and HUD display.
Extended EXIF data (aperture, shutter, ISO, focal length, exposure program, flash, dimensions) is shown in the EXIF panel (`,` key).
IPTC `Caption/Abstract` (tag 2:120) is shown in the HUD when available and can be edited during the show with `C`.

---

## Building a standalone Windows executable

QML and image files are compiled into the binary so the source is not exposed in the distribution.

**Prerequisites (one-time):**
- `pip install -r install/windows/requirements-build.txt`
- [Inno Setup 6](https://jrsoftware.org/isdl.php) installed with `iscc.exe` on `PATH`

**Full build (exe + installer) — version is read automatically from `main.py`:**

```bash
python install/windows/build.py
```

Installer output: `install\windows\dist\installer\picture-show3-setup-<version>.exe`

<details>
<summary>Manual step-by-step</summary>

```bash
# 1. Generate the app icon (one-time, or when icon.svg changes)
python install/windows/make_icon.py

# 2. Compile QML + images into a Qt resource bundle
#    Re-run whenever any .qml or img/*.svg file changes
python install/windows/compile_resources.py

# 3. Build the executable
pyinstaller install/windows/picture-show3.spec ^
    --distpath install/windows/dist --workpath install/windows/build

# 4. Build the installer
iscc install\windows\picture-show3.iss
```
</details>

### Dev vs. frozen mode

When running from source (`python main.py`), QML files are read directly from disk — edit a `.qml` file and rerun immediately, no compile step needed.

When running the built exe, QML and SVGs are loaded from the compiled resource bundle embedded in `resources_rc.py`. PyInstaller sets `sys.frozen = True`, and the app switches to `qrc:/` paths automatically.

---

## Command-line interface

See [docs/cli.md](docs/cli.md) for the full CLI reference, including all launch modes and error handling.

---

## Version

Current version is defined in `main.py` (`APP_VERSION`) and shown on the settings screen.


---

## Disclaimer

This software was developed with the assistance of AI (Anthropic Claude Code).
Architecture, feature design, and final decisions were made by the author;
code was written in collaboration with Claude.
