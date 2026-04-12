# Command-line interface

## Synopsis

```
python main.py [options] [<picture_dir>]
python main.py --kiosk [options] <picture_dir>
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `<picture_dir>` | No | Path to a folder of images to load on startup |
| `--kiosk` | No | Enable kiosk mode (requires `<picture_dir>`) |
| `--help`, `-h` | No | Print a usage summary and exit |

## Show options

These flags override the corresponding setting **for the current session only** — they are never written to the INI file. The settings page always shows the last saved values. If you change a setting in the settings page, that GUI change is saved and the CLI override for that key is released.

| Option | Description |
|---|---|
| `--autoplay [N]` | Enable autoplay; optionally set the interval to `N` seconds. Without `N` the last saved interval is kept. Any positive integer is accepted. |
| `--transition T` | Set the transition style: `fade` · `slide` · `zoom` · `fadeblack` |
| `--transition-dur MS` | Set the transition duration in milliseconds (100–3000) |
| `--sort S` | Set the sort order: `name` · `date` · `random` |
| `--scale MODE` | Set the image scale mode: `fit` · `fill` |
| `--auto-panorama` | Enable automatic panorama sweep for wide images during autoplay |
| `--no-auto-panorama` | Disable automatic panorama sweep |
| `--recursive` | Enable recursive subfolder scanning |
| `--loop` | Enable looping at the end of the show |
| `--no-loop` | Disable looping |
| `--fullscreen` | Start in fullscreen regardless of the last saved window state |

## Modes

### Normal mode

```bash
python main.py
```

Starts with the settings page. The last used folder is restored from history.

---

### Jump-start mode

```bash
python main.py <picture_dir>
python main.py --autoplay 5 --transition slide --sort date <picture_dir>
```

Loads `<picture_dir>` and launches the slideshow immediately — the settings page
is never shown on startup. The splash animation plays (logo centred, heartbeat while
scanning), then the show starts automatically once images are ready.

Pressing **Esc** during the show returns to the settings page, where the folder is
pre-filled and all controls are available. History is updated normally.

The mouse cursor is hidden in fullscreen during the splash and the show; it is
restored when the settings page is displayed.

---

### Kiosk mode

```bash
python main.py --kiosk <picture_dir>
python main.py --kiosk --recursive --loop --auto-panorama --autoplay 10 <picture_dir>
```

Designed for unattended display installations. Loads `<picture_dir>` and launches
the slideshow immediately. The settings page is never accessible.

- Pressing **Esc** during the show opens a **Quit** confirmation dialog (Y/N)
  instead of returning to settings.
- If `<picture_dir>` contains no supported images, the app exits with a non-zero
  exit code and an error message on stderr.
- Folder history is not updated.
- The mouse cursor is hidden in fullscreen throughout.

---

## Behaviour comparison

| | Normal | Jump-start | Kiosk |
|---|---|---|---|
| Settings page on startup | shown | skipped | skipped |
| Splash animation | logo drifts to header | logo stays centred | logo stays centred |
| Esc during show | → settings page | → settings page | quit dialog |
| History updated | yes | yes | no |
| No images found | empty settings page | empty settings page | exit with error |
| Cursor in fullscreen | hidden | hidden | hidden |
| Cursor on settings page | visible | visible | — |

## Error handling

Both `--kiosk` and the positional `<picture_dir>` validate that the path exists
before the Qt application starts:

```
Error: folder does not exist: /no/such/path
```

Exit code `1` is returned. In kiosk mode an additional check runs after the
background scan completes:

```
Error: no supported images found in: /empty/folder
```

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

See [README.md](../README.md#supported-image-formats) for format-specific notes.
