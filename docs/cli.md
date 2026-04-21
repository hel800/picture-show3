# Command-line interface

## Synopsis

```
python main.py [options] [<picture_dir>]
python main.py --kiosk [options] <picture_dir>
python main.py --background [options] <picture_dir>
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `<picture_dir>` | No | Path to a folder of images to load on startup |
| `--kiosk` | No | Enable kiosk mode (requires `<picture_dir>`) |
| `--background` | No | Enable background mode (requires `<picture_dir>`) |
| `--help`, `-h` | No | Print a usage summary and exit |

`--kiosk` and `--background` are mutually exclusive.

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

### Background mode

```bash
python main.py --background <picture_dir>
python main.py --background --autoplay 30 --fullscreen /mnt/photos
```

Designed for digital picture frame installations. The process starts with the GUI
**hidden** and the remote control server **always running** — the show is controlled
entirely via the remote control web page or the `/control/` HTTP API.

- The **Picture Frame** section on the remote control page provides:
  - **Start Show** / **End Show** buttons (End Show hides the GUI again, the
    process keeps running)
  - **Interval** log-scale slider (10 s – 1 day) with live adaptation
  - **Scale** toggle (Fit / Fill) with live adaptation
  - **Rescan in Background** dropdown (Off / 5 min / 10 min / 30 min / 1 h / 3 h / 6 h / 9 h / 12 h / 24 h) and a manual **Scan Now** button — rescans the folder while the show is in standby to pick up new or removed images; interval is persisted across restarts
- Show options supplied on the command line (`--autoplay`, `--sort`, `--scale`, …)
  take effect when the show is started.
- Show state is persisted under `[background_mode]` in the INI file so the show
  **auto-resumes** after a power outage or process restart without user interaction.
- Pressing **Esc** while the show is visible opens a **Quit** dialog (same as kiosk
  mode). Use **End Show** on the remote to return to background-hidden state.
- Folder history is not updated.
- If the folder contains no images (empty, filtered to zero, or network drive
  unavailable), the show window displays a "No images available" message; the
  **Start Show** button on the remote is disabled until images are found.

#### `/control/` HTTP API

All background mode control operations are available as plain HTTP GET requests,
making them easy to call from scripts, home-automation systems, or a future
schedule runner.

| Endpoint | Description | Response |
|---|---|---|
| `GET /control/start` | Show the window and start the show | `{"ok":true}` · 409 if already started |
| `GET /control/stop` | Stop the show and hide the window | `{"ok":true}` · 409 if not started |
| `GET /control/interval?value=N` | Set autoplay interval to `N` ms (10 000–86 400 000) | `{"ok":true}` · 400 on invalid value |
| `GET /control/scale?value=V` | Set scale mode (`fit` or `fill`) | `{"ok":true}` · 400 on invalid value |
| `GET /control/rescan` | Trigger an immediate folder rescan (standby only) | `{"ok":true}` · 409 if show is running |
| `GET /control/rescan-interval?value=N` | Set auto-rescan interval in seconds (`0` = off; valid: 0, 300, 600, 1800, 3600, 10800, 21600, 32400, 43200, 86400) | `{"ok":true}` · 400 on invalid value |

The `/status` endpoint returns extended fields in background mode:

```json
{
  "index": 5,
  "total": 120,
  "playing": true,
  "active": true,
  "scanning": false,
  "background_mode": true,
  "show_started": true,
  "interval": 30000,
  "scale": "fit",
  "rescan_interval": 1800
}
```

The `/control/schedule/*` route prefix is reserved for a future schedule API
(planned: daily start/stop schedules). It currently returns `501 Not Implemented`.

---

## Behaviour comparison

| | Normal | Jump-start | Kiosk | Background |
|---|---|---|---|---|
| Settings page on startup | shown | skipped | skipped | skipped (hidden) |
| Splash animation | logo drifts to header | logo stays centred | logo stays centred | logo stays centred (hidden) |
| GUI visible at startup | yes | yes | yes | no |
| Esc during show | → settings page | → settings page | quit dialog | quit dialog |
| History updated | yes | yes | no | no |
| No images found | empty settings page | empty settings page | exit with error | "no images" overlay; remote warns |
| Cursor in fullscreen | hidden | hidden | hidden | hidden |
| Cursor on settings page | visible | visible | — | — |
| Remote server | optional | optional | optional | always on |
| Show state persisted | — | — | — | yes (auto-resume) |

## Error handling

`--kiosk`, the positional `<picture_dir>`, and `--background` all validate that the
path exists before the Qt application starts:

```
Error: folder does not exist: /no/such/path
Error: background folder does not exist: /no/such/path
```

Exit code `1` is returned. In kiosk mode an additional check runs after the
background scan completes:

```
Error: no supported images found in: /empty/folder
```

Background mode does **not** exit on an empty scan — the "no images" overlay is
shown in the GUI and the Start Show button is disabled on the remote until the
folder is populated.

## Supported image formats

`.jpg` `.jpeg` `.png` `.gif` `.bmp` `.webp` `.tiff` `.tif` `.heic` `.avif`

See [README.md](../README.md#supported-image-formats) for format-specific notes.
