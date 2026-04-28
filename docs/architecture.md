# Architecture reference

Full per-component deep dives.

---

## Python layer

### `SlideshowController` (`slideshow_controller.py`)

Context property `controller` — the single source of truth exposed to QML.

**Folder loading — three-phase background pipeline**
1. **Scan** — `os.scandir` discovers image files (fast, no metadata reads); emits `scanPhase = "scan"`
2. **Sort** — name/random are instant in-memory; date sort reads EXIF `DateTimeOriginal` (tag 36867) in parallel via `ThreadPoolExecutor(max_workers=8)`; emits `scanPhase = "sort"`
3. **Ratings** — XMP ratings read in parallel only when `minRating > 0` (lazy; skipped entirely otherwise); emits `scanPhase = "filter"`

`setSortOrder` and `setMinRating` cancel running sort/ratings work immediately when images are already loaded via `_cancel_and_new_event()`. During file discovery (`_all_images` empty) they save the value and the pipeline picks it up. A `threading.Event` cancel flag + `future.result(timeout=0.1)` polling keeps cancellation responsive (~100 ms). Signals (`imagesChanged`, `scanningChanged`) are emitted only at pipeline end to avoid mid-pipeline QML re-renders stalling the splash animation.

**Public API**
- Navigation: `nextImage()`, `prevImage()`, `goTo(index)`
- Metadata accessors: `imagePath(index)`, `imageDateTaken(index)`, `imageCaption(index)`, `imageRating(index)`, `imageExifInfo(index)`
- `imageExifInfo(index)` → list of `{label, value}` dicts for the EXIF panel; labels/values wrapped in `self.tr()` for the active locale; reads Make, Model, FNumber, ExposureTime, ISO, FocalLength, ExposureProgram, Flash, PixelX/Y; exposure program strings resolved via `_exposure_program_str()`
- `apply_cli_overrides(overrides: dict)` — applies session-only CLI flags without writing to the INI file. Saves the current saved value for each overridden key in `_cli_overrides`; `_save_settings` restores those originals so the INI is never modified. When the user changes a setting via the GUI, the corresponding setter pops its key from `_cli_overrides`, making the new value permanent. `togglePlay` spends the `autoplay`/`interval` overrides on the first manual stop so that returning to settings and relaunching does not auto-start again. In background mode, `_on_stop_show()` (`main.py`) captures `isPlaying` before `stopShow()` clears it and calls `setAutoplay(was_playing)` — the live play state always wins over the spent override when the show restarts.
- `scanning` (bool) — True during any pipeline phase; `scanningChanged` signal
- `scanPhase` (str) — `"scan"` / `"sort"` / `"filter"` / `""` (idle); notified via `scanningChanged`
- `scanProgress` (int) — files processed in current metadata phase (0 outside metadata phases); `scanProgressChanged` signal
- `cancelAll()` — cancels all background workers; connected to `app.aboutToQuit` in `main.py`
- Signals: `imagesChanged`, `currentIndexChanged`, `isPlayingChanged`, `settingsChanged`, `folderHistoryChanged`, `errorOccurred(str)`, `scanningChanged`, `scanProgressChanged`, `ratingWritten(int)`, `captionWritten(int)`

**Metadata caches**
- `_date_cache: dict[str, datetime]` — populated by `_parallel_date_sort`; only missing files are read on re-sort; cleared on each successful scan result and on the scan error path
- `_rating_cache: dict[str, int]` — populated by the ratings pipeline; `setMinRating` and `_on_sort_complete` use `len(_rating_cache) < len(_all_images)` (not `not _rating_cache`) to decide whether to re-run — a single in-show `writeImageRating` call leaves a partial cache that would otherwise cause main-thread I/O

**XMP rating write — `writeImageRating(index, rating)` `@Slot(int, int, result=bool)`**
Validates path, calls `_write_xmp_rating`, updates `_rating_cache`, emits `ratingWritten`.

`_write_xmp_rating(path, rating)` static — atomically patches XMP Rating in JPEG: reads raw bytes, scans JPEG APP markers to find XMP APP1, calls `_modify_xmp_rating_str`, writes to a temp file in the same directory, Pillow `img.verify()`, then `os.replace`; raises `ValueError`/`OSError` on failure; JPEG-only.

`_modify_xmp_rating_str(xmp_str, rating)` static — strips both attribute-form (`xmp:Rating="N"`) and element-form (`<xmp:Rating>`) occurrences, then injects `xmp:Rating="N"` onto the first `rdf:Description`; rating 0 removes without injecting; handles missing/empty XMP by generating a minimal XMP envelope; re-injects `xmlns:xmp` declaration if it was carried only by the removed element.

**IPTC caption write — `writeImageCaption(index, caption)` `@Slot(int, str, result=bool)`**
Validates path, calls `_write_iptc_caption`, invalidates `_exif_cache` for that index, emits `captionWritten`.

`_write_iptc_caption(path, caption)` static — atomically patches IPTC Caption/Abstract (dataset 2:120) in JPEG: reads raw bytes, walks JPEG APP markers to find APP13 with "Photoshop 3.0\0" signature, calls `_modify_iptc_caption_bytes`, builds new APP13 segment, writes to temp file, Pillow `img.verify()`, then `os.replace`; JPEG-only.

`_modify_iptc_caption_bytes(app13_payload, caption)` static — byte-level IPTC patcher: parses 8BIM resource blocks (type 0x0404 = IPTC-NAA), strips any existing (2, 120) record, injects a new one unless caption is empty; preserves all other 8BIM blocks; builds a minimal PS3 envelope when no APP13 exists; handles extended-length IPTC records (high bit of first length byte).

**Other notes**
- Folder history: last 100 folders (`_MAX_HISTORY = 100`); `QSettings` returns bare `str` (not `list`) when only one folder is stored — handled with `match/case` in `_load_settings`
- Deferred initial scan: `_load_settings()` sets `_scanning = True` synchronously then defers `_scan_images()` via `QTimer.singleShot(0, ...)` so the window renders before I/O begins
- `kioskMode`: `@Property(bool, notify=kioskModeChanged)` — CLI flag only, not persisted; suppresses folder history update in `startShow` and skips loading `_folder_history[0]` on init
- `jumpStart`: `@Property(bool, constant=True)` — True when started with a bare `<picture_dir>` argument; same init behaviour as kiosk but Esc exits to settings and history is updated normally
- `backgroundMode`: `@Property(bool, constant=True)` — True when started with `--background`; GUI starts hidden; checked in `main.qml` `onStartShow` to skip the normal show-start sequence (Python handles it instead). Also causes `kiosk_mode=True` in `main.py` (`kiosk_mode = kiosk_folder is not None or background_folder is not None`) so that `kioskMode` drives `_autoLaunch` and history suppression for background mode.
- `suppressNextPlayAnim()` slot — sets a one-shot `_suppress_next_play_anim` flag; `takePlayAnimSuppression()` slot (returns bool, clears flag) — called by `SlideshowPage.onIsPlayingChanged` to skip the play/pause popup on remote-triggered start/stop

---

### `SlideshowImageProvider` (`image_provider.py`)

Custom `QQuickImageProvider` at `image://slides/<index>`.
- Background thread preloads 2 images ahead, 1 behind the current index; thread-safe cache eviction when the window moves
- `QImageReader` with `setAutoTransform(True)` for EXIF orientation; synchronous fallback on cache miss
- Pillow fallback loader (`_pillow_to_qimage`) for formats Qt doesn't support (HEIC, AVIF); invoked when `QImageReader` returns a null image; requires `pillow-heif` for HEIC/HEIF

---

### `QrImageProvider` (`qr_provider.py`)

Custom `QQuickImageProvider` at `image://qr/<url-encoded-text>`.
- `id` parameter must be URL-encoded in QML (`encodeURIComponent(remoteServer.url)`) and decoded in Python (`urllib.parse.unquote(id)`)
- Uses `qrcode[pil]` to render a PIL image, converts to `QImage` via PNG buffer
- In-memory cache keyed by decoded URL — each unique URL is generated only once
- Use `smooth: false` on the QML `Image` to keep QR pixel blocks crisp

---

### `RemoteServer` (`remote_server.py`)

Built-in HTTP server (Qt `QTcpServer`, no extra dependencies) — context property `remoteServer`.
- Serves a touch-friendly web page at the machine's LAN IP on a configurable port (default 8765)
- Standard endpoints: `GET /` (UI), `/next`, `/prev`, `/toggle`, `/toggle-hud`, `/toggle-exif`, `/preview` (JPEG thumbnail, generated off-thread), `/interval?value=N` (1 000–99 000 ms), `/status` (JSON), SVG assets
- Background mode adds: `/control/start`, `/control/stop`, `/control/interval?value=N` (10 000–86 400 000 ms), `/control/scale?value=V` (`fit`/`fill`), `/control/transition?value=V` (`fade`/`slide`/`zoom`/`fadeblack`), `/control/rescan` (409 if show running), `/control/rescan-interval?value=N` (seconds; valid set: {0, 300, 600, 1800, 3600, 10800, 21600, 32400, 43200, 86400}); `/control/schedule/*` reserved (501)
- `/status` returns `{ index, total, playing, active, scanning, hud_visible, exif_visible, caption, rating, interval }`; extended in background mode with `background_mode`, `show_started`, `scale`, `transition`, `rescan_interval`. The `caption` field is cached per current image path (invalidated on `imagesChanged` / `captionWritten`) so polling does not re-parse IPTC every 3 s.
- Signals: `startShowRequested`, `stopShowRequested`, `intervalChangeRequested(int)`, `scaleChangeRequested(str)`, `transitionChangeRequested(str)`, `toggleExifRequested`, `rescanRequested`, `rescanIntervalChangeRequested(int)`, `showStartedChanged`, `exifVisibleChanged`
- `setShowActive(bool)` enables/disables browser nav buttons; `setShowStarted(bool)` / `showStarted` property track whether the show window is currently visible; `setExifVisible(bool)` / `exifVisible` mirror the QML `_exifVisible` so the remote "Show/Hide Details" button label tracks the live panel state; `setRescanInterval(int)` syncs the current auto-rescan interval into server state for `/status` reporting
- `setPort(int)` allows dynamic port changes; `setShowActive(bool)` slot controls button state
- In background mode the server always starts regardless of the `remoteEnabled` setting
- The web UI shows two tabs: **Remote** (standard nav controls) and **Picture Frame** (Start/Stop Show buttons, non-linear interval slider 10 s–24 h, Fit/Fill scale chips, **Rescan in Background** section: interval dropdown Off/5 min…24 h + manual **Scan Now** button — rescan disabled while show is running or scan is in progress); the browser detects an offline server via `AbortController` 2.5 s timeout and disables all buttons
- SVG files served via `_read_img(filename)`: reads from `qrc:/img/` (frozen) or `img/` folder (dev)

---

### `WindowHelper` (`main.py`)

Tracks fullscreen state independently of the OS window to avoid Qt timing issues — context property `windowHelper`.
- `saveWindowed()` slot — QML **must** call this immediately before `win.showFullScreen()`; this is the only reliable point where windowed dimensions are still correct on Windows (after `visibilityChanged` the OS has already resized the window)
- Restores saved windowed geometry 50 ms after leaving fullscreen (deferred to let the window settle)
- `freeze()` called at quit to prevent state flip during the close sequence
- `setCursorHidden(bool)` — `QGuiApplication.setOverrideCursor` (global) + `QWindow.setCursor` (per-window, forces immediate platform dispatch)
- `windowVisibleChanged = Signal(bool)` — emitted in `_on_vis_changed`; `windowVisible: @Property(bool, notify=windowVisibleChanged)` — consumed by `SettingsPage` via `Connections { target: windowHelper }` to re-trigger the splash animation on each background-mode Start Show. Note: `Window.window` (a `QQuickWindow`) cannot be used as a Connections target in QML — this signal/property pair is the correct bridge.

---

### Frozen/dev mode (`main.py`, `remote_server.py`)

`_FROZEN = getattr(sys, "frozen", False)` — PyInstaller injects `sys.frozen = True` before any user code runs.

- **Dev** (`python main.py`): QML from filesystem via `QUrl.fromLocalFile`; SVGs read from `img/`; no compile step needed
- **Frozen** (built exe): `import resources_rc` registers all QML and SVG files under `qrc:/`; QML loaded from `qrc:/qml/main.qml`; SVGs read via `QFile(":/img/<name>")` in `_read_img()`
- QML `../img/` relative paths work unchanged in both modes

`_parse_args()` uses `argparse` and returns an 8-tuple `(kiosk_folder, start_folder, background_folder, force_fullscreen, overrides, qt_argv, on_show_start, on_show_stop)`. `overrides` is a dict of INI keys → values for show options passed on the CLI; it is passed to `controller.apply_cli_overrides()` after the controller is initialised. Unknown flags are forwarded to Qt via `qt_argv` so Qt's own flag handling still works. `on_show_start` / `on_show_stop` are `str | None` — shell commands wired into `_setup_background_mode()` for display power control (see below).

Build: `python install/windows/build.py` — reads `APP_VERSION` from `main.py`, runs make_icon → compile_resources → PyInstaller → Inno Setup → cleanup. `a.binaries` is filtered in the spec to strip large unused Qt DLLs (e.g. `Qt6WebEngineCore.dll` at 193 MB); translations are stripped from `a.datas` the same way.

---

### `UpdateChecker` (`update_checker.py`)

`QObject` with `updateAvailable(str)` signal — context property `updateChecker`. `check(current_version)` spins a daemon thread that GETs `https://api.github.com/repos/hel800/picture-show3/releases/latest`, compares version tuples (numeric components only), and emits the signal if the remote tag is strictly newer. Cross-thread emission is safe — PySide6 queues it to the receiver's thread automatically. All network errors swallowed silently. Triggered 3 s after startup (`QTimer.singleShot`) only when `controller.updateCheckEnabled` is True. `SettingsPage` connects `onUpdateAvailable` and shows a clickable badge.

---

## QML layer

### Navigation

`StackView` in `main.qml` — `SettingsPage` is the initial item; `SlideshowPage` is pushed on show start and popped on exit. Cursor hidden unconditionally before push via `windowHelper.setCursorHidden(true)`; restored via `Component.onDestruction` in `SlideshowPage`.

---

### `SettingsPage.qml`

**Splash animation**: logo fades in + scales up centred on screen, then drifts to the header position; header logo has `opacity: 0` at startup; a `ScriptAction` sets `headerLogo.opacity = 1` and hides the overlay in the same frame — no double-image flicker. Animated sun watermark (`logo_sun.svg`) in bottom-right background.

**Controls**: folder input + Browse button (opens at current folder) + history button with inline `KeyHint` badges. Recent-folders popup: Up/Down (no wrap-around), Enter to select. Star rating filter popup (All / 1–5 stars). Transition style chips (fade/slide/zoom/fadeblack). Sort order chips (name/date/random). Loop + Autoplay toggles. Autoplay interval slider (1–99 s). Advanced Settings link → `AdvancedSettingsDialog` (four tabs: General, Controls, HUD, Remote). Remote URL + QR button. Quit confirm popup (Y/N/←/→/Enter).

**`_canStart`**: `controller.imageCount > 0 && !controller.scanning`. Start button disabled and relabelled "Scanning…" while scanning. Scanning status row: hourglass + "Scanning… N / total" driven by `scanProgress`.

**Kiosk / jump-start**: `_autoLaunch: controller.kioskMode || controller.jumpStart` — logo stays centred in splash (no drift to header), key/mouse events absorbed during splash. After splash: if images are loaded, `kioskLaunchAnim` fires; otherwise a breathing pulse plays until `onScanningChanged` or `onImagesChanged` confirms both `scanning=false` and `imageCount>0`. Both handlers check `&& splashOverlay.visible` — `triggerSlideIn()` sets `splashOverlay.visible = false` on return from show, permanently blocking re-launch on subsequent scans. `onScanningChanged` fires before `_apply_filter` sets `imageCount`, so both handlers are needed and the one that fires last triggers launch.

**Background mode** also has `_autoLaunch = True` (because `kioskMode = True`). Both `onScanningChanged` and `onImagesChanged` add a guard `if (controller.backgroundMode && !windowHelper.windowVisible) return` — launch is deferred until the window becomes visible. A `Connections { target: windowHelper; function onWindowVisibleChanged(visible) }` block in `SettingsPage` triggers `splashAnim.restart()` followed by `kioskLaunchAnim` on each hide→show transition, so the full splash animation plays on every Start Show press.

**Cursor**: `Window.onVisibilityChanged` calls `windowHelper.setCursorHidden(Window.visibility === Window.FullScreen)`. `triggerSlideIn()` unconditionally calls `setCursorHidden(false)` on return from show.

**AdvancedSettingsDialog keyboard navigation**: zero-size `Item { id: keyHandler; focus: true }` inside `contentItem` receives all key events. `_section` (0–3) tracks active tab; `_focusedOption` tracks highlighted option; `_doneFocused` bool tracks Done button focus. TextInput (port field) focused via Enter; returns focus to `keyHandler` via `Qt.callLater(keyHandler.forceActiveFocus)` — synchronous `forceActiveFocus()` inside `TextInput Keys.onPressed` is unreliable. `onActiveFocusChanged` saves port value on focus loss to avoid `forceActiveFocus` → focus loss → `editingFinished` → infinite recursion.

---

### `SlideshowPage.qml`

**Dual-layer system**: `layerA` / `layerB` with explicit `width: parent.width; height: parent.height` (not `anchors.fill`) so the `x` property is free for the slide animation.

**Transitions**:
| Style | Mechanism |
|---|---|
| `fade` | `ParallelAnimation` on `opacity` of both layers |
| `slide` | 3-phase `SequentialAnimation`: outgoing zooms out (20 % of duration, scale 1.0→0.9), both layers slide (`x`, 60 %), incoming zooms back to full size (20 %); incoming starts already at scale 0.9 off-screen so the transition feels continuous |
| `zoom` | Parallel fade + scale on incoming layer |
| `fadeblack` | `SequentialAnimation`: outgoing fades out, then incoming fades in |

**Cursor**: fullscreen → `Qt.BlankCursor`; windowed → `Qt.ArrowCursor`. Mouse single-click navigation guarded by a 200 ms `Timer`; `onDoubleClicked` cancels the timer, toggling fullscreen without advancing the image.

**`onImagesChanged`**: calls `showImage(true)` whenever `imageCount > 0` — covers kiosk mode (show starts before scan completes) and re-sort/re-filter while the show is active.

**HUD** — two mutually exclusive components driven by `controller.hudStyle`:

- **`HudBar.qml`** (`z: 10`, style `"fundamental"`): full-width bottom strip; index, filename, IPTC caption, star rating, EXIF date, play/pause state, key hints. `hudVisible` drives a state machine with 300 ms opacity transition. Height/fonts/margins scale with `hudScale` = `controller.hudSize / 100`.
- **`FloatingHud.qml`** (`z: 10`, style `"floating"`): pill-shaped overlay centred horizontally, `anchors.bottom` with a `hudScale`-dependent margin; 80 % of screen width, 8 % of screen height; `_contentH = _hudH * 0.28` drives all font and icon sizes. Shows counter, separator, caption (scrolling `SequentialAnimation on x` when text overflows), optional star row, optional date. Open: fade-in 260 ms OutCubic + nudge-up 320 ms OutBack; close: fade-out + nudge-down 200 ms. `_stoppingForReopen` guard prevents `closeAnim.onStopped` from resetting `_slideOffset` when `open()` interrupts an in-progress close. **Inline caption edit**: pressing **C** (when floating HUD is visible) replaces the caption `Text` with a `TextInput`; stars/date remain visible; key hints (`↵` save · `Esc` cancel · `Tab Tab` copy prev) appear anchored to the bottom of the HUD box; border turns accent-coloured. `onActiveFocusChanged` re-grabs focus via `Qt.callLater` if lost (no mouse in fullscreen); SlideshowPage `Keys.onPressed` fallback handles Enter/Esc and calls `refocusEdit()`. Signals `editStarted`/`editClosed`/`editConfirmed(text)` drive autoplay pause/resume in SlideshowPage. **`confirmEdit()` ordering**: `editing = false` is set *before* `editConfirmed` is emitted — if the signal fired first, `onEditConfirmed`'s `forceActiveFocus()` call would remove focus from `captionEditInput` while `editing` is still `true`, causing `onActiveFocusChanged` to schedule a `Qt.callLater(forceActiveFocus)` that re-steals focus after cleanup. **DPI-invariant key hints**: the HUD height is `parent.height * 0.08` (screen-proportional, unaffected by `QT_SCALE_FACTOR`), so the caption edit key hints multiply all sizes by `100 / controller.uiScale` to counteract the DPI scale factor and stay the same physical size as the HUD. **Content crossfade**: `crossfadeContent()` runs a `SequentialAnimation` — fade out `contentRow` over `transitionDuration / 2`, `ScriptAction` calls `refreshDisplay()` to swap in new values at opacity 0, fade in over `transitionDuration / 2`. Display values (`_displayCount`, `_displayCaption`, `_displayRating`, `_displayDate`) are plain (non-binding) properties with no automatic update handlers — updated only by `refreshDisplay()` or the crossfade midpoint script.

`SlideshowPage._floatingHudClearance`: `FloatingHud._hudH + 40` when floating HUD is visible, else 0. Applied to the `y` position of jump/rating/caption dialogs and to `ExifPanel.anchors.bottomMargin` so no overlay is obscured by the floating HUD. Hidden by default; toggle **I**; style persisted as `hudStyle` INI key.

**EXIF panel** (`ExifPanel.qml`, `z: 11`): opened **,**, closed **,** or **Esc**, auto-closes on navigation or when a higher-z overlay opens (`_closeExifIfOpen()` helper). Positioned `anchors.bottom: hud.top`. Animation: `transform: Translate { y: _slideOffset }` — 20 px below at opacity 0; fade-in 260 ms OutCubic + bounce-up 320 ms OutBack; close 200 ms. `exifData` set before `open()` so content never changes mid-animation. `_stoppingForReopen` flag prevents `closeAnim.onStopped` from clearing data when `open()` interrupts an in-progress close. Caption row scrolls when text overflows (`SequentialAnimation on x`, `from: 0` ensures scroll starts from left on reopen). When `!hudVisible`, up to 3 extra rows appended: Rating, Date, Caption. Label column width is locale-aware via `Number(qsTr("100", "exif_label_width"))`.

**Play/pause popup** (`z: 20`): fixed 300×88 px overlay; triggered by `isPlayingChanged`; fades in 120 ms, holds 3 s (with depleting countdown border on the icon), fades out 400 ms. While the **play** popup is visible, `↑`/`↓` or `1`–`9` pause autoplay and enter interval edit mode (`_ppEditMode`); `↵` confirms the new interval and restarts autoplay; `Esc` cancels and leaves autoplay stopped. `0`–`9` and `↑`/`↓` are blocked during the **pause** popup. The autoplay timer is frozen via `controller.pauseInterval()` when the popup appears and restarted via `controller.restartInterval()` in `playPauseAnim.onFinished`.

**No-images overlay** (`z: 25`): shown when `controller.imageCount === 0 && !controller.scanning` **or when the currently displayed image file is missing/unreadable** (`_activeImgError: (showingA ? imgA : imgB).status === Image.Error`). In the error case the icon turns amber (`Theme.statusWarn`), the title reads "Image not available", a filename line is shown, and the subtitle reads "The file may have been moved or deleted." The `_listLocked` property (set in `Component.onCompleted` after the first `showImage`) prevents `onImagesChanged` from refreshing the image list during an active show — the list is frozen after first display.

**Jump dialog** (`z: 30`): opened **J**; `IntValidator` (1–imageCount); pauses autoplay; Enter to jump, Esc to cancel.

**Rating overlay** (`z: 30`): opened **0**–**5**. Stars cascade in one-by-one via a 55 ms interval `Timer` incrementing `_starsRevealedCount` 0→5; each star fades in 220 ms OutCubic + bounces up from 14 px via `transform: Translate { Behavior on y }`. The animation is skipped when the overlay is already open and the same rating is pressed again (`sameRating = ratingOverlay.visible && r === _pendingRating`). **↵** → `controller.writeImageRating`; **Esc** cancels. `onRatingWritten` restores `hudRating` QML binding via `Qt.binding()` so navigation keeps updating it.

**Caption overlay** (`z: 30`): opened **C**; loads current caption into `TextInput`; closes EXIF panel if open; pauses autoplay. Double-Tab within 600 ms copies previous image's caption (`_lastTabMs` tracks first Tab). **↵** → `controller.writeImageCaption` then close. `onCaptionWritten` restores `hudCaption` binding via `Qt.binding()`. Closes without saving on image navigation.

**Leave overlay** (`z: 50`, background mode only): triggered by `function startLeaveAnim()` (called from `main.qml` `Connections { target: remoteServer; onStopShowRequested }`). `SequentialAnimation`: fade to dark + logo fade-in (600 ms) → logo hold (2 s) → logo shrink+fade (1 s). `ScriptAction` at end emits `signal leaveAnimDone()`, which causes `main.qml` to call `stack.pop(null, StackView.Immediate)` for a clean GPU frame before Python defers `win.hide()` by 3700 ms (100 ms buffer over the 3600 ms animation total). A `_leavingShow` flag in `main.qml` prevents a second `/control/stop` from re-triggering the leave animation while it is already running. Before the animation begins, `_on_stop_show()` captures `controller.isPlaying` and calls `controller.setAutoplay(was_playing)` to persist the live play state for the next Start Show. `--on-show-start CMD` / `--on-show-stop CMD` CLI flags hook into `_setup_background_mode()`: the start command runs in a daemon thread before `_do_show()` is called (the Qt event loop stays responsive; the window only appears after `CMD` exits); the stop command is launched as a fire-and-forget daemon thread in `_finish_stop()` after `win.hide()`.

**Panorama mode**: activated **P**; requires image aspect ratio ≥ 1.3× screen ratio. `startPanorama()` enables `layer.layer` at panorama resolution (capped 4096 px wide), then `panoramaEnterAnim` (1400 ms InOutCubic scales up + pans to right half). After enter, `_panoramaScrollRight()` / `_panoramaScrollLeft()` alternate via `onStopped`; speed 250 px/s. `stopPanorama()` sets `_panoCleanupPending = true`, stops scroll, runs `panoramaExitAnim` (800 ms OutCubic); `onStopped` disables layer and restores state. `_panoramaAbort()`: instant teardown on resize. Key handling while active: **P**/**Esc** → stop; **←**/**→** → `_pendingNav` then stop (navigation fires in exit `onStopped`); **I** → HUD; all other keys absorbed.

**Auto panorama** (`controller.autoPanorama`, `_autoPanoramaActive`): when enabled and autoplay is running, `_tryAutoPanorama()` starts a single-sweep panorama — enter animation + one right-scroll, then `stopPanorama()` + `_pendingNav = 1` to auto-advance. Triggered from `_checkPendingPanorama()` (after each transition), imgA/imgB `onStatusChanged` (slow-loading images), and `onIsPlayingChanged` (Space starts autoplay while suitable image is already on screen).

Guards:
- **`_autoPanoramaSkip`** — prevents restart on the same image after **Esc**/**P**/**←** cancellation; cleared on forward navigation (`navDir >= 0` in `onCurrentIndexChanged`).
- **`_suppressPlayAnim`** — checked in `onIsPlayingChanged` to skip `_tryAutoPanorama()` during silent play-state changes from the quit dialog. Panorama itself no longer toggles play (it uses `controller.pauseInterval()` / `restartInterval()`), so this flag is no longer set or cleared by panorama code.
- **`_suppressPanoCheck`** — set at the top of `showImage()` and cleared at every return path. Blocks `_checkPendingPanorama()` from running while `stopAll()`'s explicit `fadeAnim.stop()` synchronously fires `onStopped`. Without it, navigating away from a fade-in to a panorama image would launch a panorama on the layer that's about to be reused, producing a simultaneous fade + scroll.
- **`_pendingShowAfterPano`** — set in `onCurrentIndexChanged` when external navigation (remote prev/next, jump-to) arrives while `panoramaActive` is true. The handler calls `stopPanorama()` to run the 800 ms zoom-back animation; the cleanup picks up `pendingShow` and calls `showImage(true)` to display the already-changed `currentIndex`. Replaces the old `_panoramaAbort()` instant teardown.
- **`_pendingManualNav`** — set by the keyboard panorama-mode Right/Left handlers so the cleanup advances unconditionally regardless of `controller.isPlaying`. Auto-panorama leaves it false so the natural-exit advance is gated on `isPlaying` (user-paused-mid-sweep ends the show on the current image).

`_autoPanoramaActive` is cleared unconditionally at the top of `panoramaExitAnim.onStopped` (belt-and-suspenders) — without this guard, the graceful external-nav path would leave the flag stuck true and silently suppress all future auto-panorama sweeps until app restart.

The play/pause popup also gates its timer restart on `!panoramaActive`: `playPauseAnim.onFinished: if (controller.isPlaying && !root.panoramaActive) controller.restartInterval()`. Without that, the ~3.3 s popup could restart the autoplay timer mid-sweep on a longer panorama and fire `nextImage()` before the panorama finished, advancing one image too early.

---

### `Theme.qml`

Singleton registered in `qmldir`; all QML files `import "."` and reference `Theme.<token>`.

| Group | Tokens |
|---|---|
| Backgrounds | `bgDeep`, `bgGradEnd`, `bgCard`, `surface`, `surfaceHover`, `borderMuted` |
| Accent | `accentDeep`, `accentPress`, `accent`, `accentLight` |
| Text | `textPrimary`, `textSecondary`, `textSubtle`, `textMuted`, `textDisabled`, `textGhost` |
| Status | `statusOk`, `statusWarn` |
| Misc | `starInactive` |
| Semi-transparent overlays | `overlayDim`, `overlayDimLight`, `panelBg`, `hudBg`, `panelBorderStrong`, `panelBorderMid`, `panelBorderSubtle`, `panelBorderFaint`, `panelDivider`, `panelRowBg`, `panelSectionBg`, `panelSeparator` |
| Overlay animation | `animFadeInDuration`, `animSlideInDuration`, `animFadeOutDuration`, `animSlideOffset`, `animSlideOvershoot` |

---

### `HelpOverlay.qml`

Two-column modal: settings-page shortcuts on left, slideshow shortcuts on right. Staggered row reveal (35 ms/row). Close **?** or **Esc**; **F** toggles fullscreen while open. Opened from both pages via **F1**.

---

### `KeyHint.qml` / `ThemedIcon.qml`

`KeyHint`: bordered rounded-rect key-cap badge; properties `label` (str), `uiScale` (real, default 1.0).

`ThemedIcon`: SVG icon with `MultiEffect` color tinting; properties `source`, `size`, `iconColor`. SVG style guide: `icon_play/pause/jump.svg` use 32×32 viewBox + rounded-rect border (`rx="6"`, stroke 50% opacity); all other icons use 24×24, no border.

---

## See also

- [README.md](../README.md) — user-facing feature overview, setup, build, and translations
- [cli.md](cli.md) — full command-line reference, launch modes, and the HTTP control API
- [user-flow.md](user-flow.md) — page state diagram, keyboard maps, overlay z-order
