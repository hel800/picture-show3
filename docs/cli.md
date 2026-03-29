# Command-line interface

## Synopsis

```
python main.py [--kiosk] [<picture_dir>]
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `<picture_dir>` | No | Path to a folder of images to load on startup |
| `--kiosk` | No | Enable kiosk mode (requires `<picture_dir>`) |

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
