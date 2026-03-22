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
| **Star filter** | Filter the playlist to images at or above a minimum XMP star rating (1–5) |
| **Jump to image** | Instantly jump to any image by number with a live preview |
| **Panorama mode** | Auto-detects wide images and scrolls them smoothly across the screen |
| **Mouse navigation** | Optional left/right click to advance or go back (toggle in Advanced settings) |
| **Phone remote** | Scan the QR code or open the URL on any phone on the same Wi-Fi |
| **Keyboard** | Full keyboard control on both the settings screen and during the show |
| **Help overlay** | Press `?` at any time to see all keyboard shortcuts |
| **Cursor** | Hidden in fullscreen; visible in windowed mode |
| **Multilingual** | UI language selectable in Advanced settings; `Auto` follows system locale |

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

Tests require no display and create all fixture images at runtime — no test assets are committed to the repo.

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

---

## Advanced settings

Reachable via the **Advanced settings ›** link or by pressing `V` on the settings screen.
Settings are grouped into four tabs:

| Tab | Options |
|---|---|
| **General** | Transition duration (100–3000 ms) · UI language |
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
language = de     ; e.g. de, en, auto
```

### Adding a new language

1. Copy `translations/picture-show3_en.ts` to `translations/picture-show3_<code>.ts`
   (e.g. `picture-show3_fr.ts` for French).
2. Open the file in **Qt Linguist** (`pyside6-linguist`) or any text editor and fill in the `<translation>` elements.
3. Compile the `.ts` file to a `.qm` file:
   ```bash
   .venv/Scripts/pyside6-lrelease translations/picture-show3_fr.ts \
       -qm translations/picture-show3_fr.qm
   ```
4. Restart the app — the new language appears automatically in the language selector.

Commit the `.ts` source file; `.qm` files are generated and excluded from git.

### Keeping translations up to date

After adding or changing `qsTr()`/`self.tr()` strings in the source, regenerate the `.ts` files:

```bash
.venv/Scripts/pyside6-lupdate qml/*.qml slideshow_controller.py \
    -ts translations/picture-show3_en.ts translations/picture-show3_de.ts
```

New strings are added with `type="unfinished"`; existing translations are preserved.
Compile all `.ts` files at once:

```bash
.venv/Scripts/pyside6-lrelease translations/picture-show3_*.ts
```

The build script (`install/windows/compile_resources.py`) runs `pyside6-lrelease` automatically as part of the build.

---

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

HEIC/HEIF files require the `pillow-heif` package (included in `requirements.txt`).
AVIF support requires Pillow ≥ 9.1 (satisfied by the `≥ 10.0` constraint).

EXIF orientation is applied automatically.
EXIF `DateTimeOriginal` is read for date-based sorting and HUD display.
IPTC `Caption/Abstract` (tag 2:120) is shown in the HUD when available.

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

## Version

Current version is defined in `main.py` (`APP_VERSION`) and shown on the settings screen.


---

## Disclaimer

This software was developed with the assistance of AI (Anthropic Claude Code).
Architecture, feature design, and final decisions were made by the author;
code was written in collaboration with Claude.
