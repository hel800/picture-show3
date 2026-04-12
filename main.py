# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause - see LICENSE for details.
"""
picture-show3 - main entry point
Requires: Python >= 3.14  |  PySide6 >= 6.7
"""
import sys
import os
import configparser
import ctypes
from pathlib import Path

from PySide6.QtCore import QLocale, QObject, QSettings, QTimer, QTranslator, QUrl, Qt, Slot
from PySide6.QtGui import QCursor, QGuiApplication, QIcon, QImageReader, QWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from image_provider import SlideshowImageProvider
from qr_provider import QrImageProvider
from remote_server import RemoteServer
from slideshow_controller import SlideshowController
from update_checker import UpdateChecker

APP_VERSION = "3.2 dev"

_FROZEN = getattr(sys, "frozen", False)

# Tell Windows this is its own app, not a Python script - gives it a distinct
# taskbar button with the correct icon instead of grouping under python.exe.
if sys.platform == "win32":
    ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("picture-show3")


def _base_dir() -> Path:
    """Return the resource root - works from source and when frozen by PyInstaller."""
    if _FROZEN:
        return Path(sys._MEIPASS)          # type: ignore[attr-defined]
    return Path(__file__).parent


# Deployed (frozen): load QML from the compiled Qt resource bundle (qrc:/).
# Dev (source):      load QML from the filesystem for instant edit→run.
if _FROZEN:
    import resources_rc  # noqa: F401  - registers qrc:/ paths with Qt
    _QML_ROOT = QUrl("qrc:/qml/main.qml")
else:
    _QML_ROOT = QUrl.fromLocalFile(str(_base_dir() / "qml" / "main.qml"))


def _apply_ui_scale() -> None:
    """
    Read uiScale from the INI file and set QT_SCALE_FACTOR before QGuiApplication
    is created.  QT_SCALE_FACTOR must be set before the application object exists,
    so we read the persisted value directly with configparser instead of QSettings.
    """
    if sys.platform == "win32":
        base = os.environ.get("APPDATA", "")
        if not base:
            return
        ini = Path(base) / "picture-show3" / "picture-show3.ini"
    elif sys.platform == "darwin":
        ini = Path.home() / "Library" / "Preferences" / "picture-show3" / "picture-show3.ini"
    else:
        xdg = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
        ini = Path(xdg) / "picture-show3" / "picture-show3.ini"

    if not ini.exists():
        return

    cfg = configparser.ConfigParser()
    cfg.read(str(ini), encoding="utf-8")
    try:
        # QSettings IniFormat lowercases keys and stores top-level keys under [General]
        val = int(cfg.get("General", "uiscale", fallback="100"))
    except (ValueError, configparser.Error):
        return

    if val != 100:
        os.environ.setdefault("QT_SCALE_FACTOR", str(val / 100))


def _install_translator(app: QGuiApplication) -> QTranslator | None:
    """
    Load the .qm translation file matching the configured or system language.
    Falls back silently (stays English) if no matching file is found.
    """
    s = QSettings()
    lang = s.value("language", "auto")
    if lang == "auto":
        lang = QLocale.system().name()   # e.g. "de_DE" or "de"

    translations_dir = _base_dir() / "translations"
    translator = QTranslator(app)

    # Try exact locale match ("de_DE"), then language-only ("de")
    for candidate in dict.fromkeys([lang, lang.split("_")[0]]):
        if translator.load(str(translations_dir / f"picture-show3_{candidate}.qm")):
            app.installTranslator(translator)
            return translator

    return None


class WindowHelper(QObject):
    """
    Exposed to QML as 'windowHelper'.

    Tracks fullscreen state independently of the OS window state so that
    _save_window() gets reliable values even if Qt mutates the window during
    the close sequence.

    QML contract:
      • Call windowHelper.saveWindowed() immediately before win.showFullScreen()
        (not needed before showNormal() - that is handled automatically).
    """

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._win = None
        self._is_fullscreen = False   # our own authoritative tracking
        self._quitting = False        # set on quit to freeze state
        self._cursor_hidden = False   # tracks whether we pushed a BlankCursor override

    # ── setup ──────────────────────────────────────────────────────────────

    def set_window(self, win) -> None:
        self._win = win
        win.visibilityChanged.connect(self._on_vis_changed)

    # ── QML-callable slots ─────────────────────────────────────────────────

    @Slot(bool)
    def setCursorHidden(self, hidden: bool) -> None:
        """
        Hide or show the mouse cursor at the application level.
        Uses QGuiApplication.setOverrideCursor so the cursor is suppressed
        regardless of hover state - MouseArea.cursorShape only fires lazily
        on the first pointer move, which leaves the cursor visible at (0,0)
        on Linux/RPi until the user moves the mouse.
        """
        if hidden == self._cursor_hidden:
            return
        if hidden:
            QGuiApplication.setOverrideCursor(QCursor(Qt.CursorShape.BlankCursor))
        else:
            QGuiApplication.restoreOverrideCursor()
        self._cursor_hidden = hidden

    @Slot()
    def saveWindowed(self) -> None:
        """
        Call from QML immediately before win.showFullScreen().
        Saves the current windowed geometry while the window is still windowed.
        """
        if self._win is None:
            return
        win = self._win
        s = QSettings()
        s.setValue("window/width",  win.width())
        s.setValue("window/height", win.height())
        s.setValue("window/x",      win.x())
        s.setValue("window/y",      win.y())
        self._is_fullscreen = True   # we are about to go fullscreen

    # ── Python-internal API ────────────────────────────────────────────────

    @property
    def is_fullscreen(self) -> bool:
        return self._is_fullscreen

    def freeze(self) -> None:
        """Freeze state before reading is_fullscreen on quit."""
        self._quitting = True

    # ── private ────────────────────────────────────────────────────────────

    def _on_vis_changed(self, new_vis: QWindow.Visibility) -> None:
        if self._quitting:
            return
        if new_vis == QWindow.Visibility.FullScreen:
            self._is_fullscreen = True
        elif new_vis == QWindow.Visibility.Windowed:
            was_fullscreen = self._is_fullscreen
            self._is_fullscreen = False
            if was_fullscreen:
                self._restore_windowed()

    def _restore_windowed(self) -> None:
        s = QSettings()
        if not s.contains("window/width"):
            return
        win = self._win

        def _do() -> None:
            avail = QGuiApplication.primaryScreen().availableGeometry()
            w = min(int(s.value("window/width")),  avail.width())
            h = min(int(s.value("window/height")), avail.height())
            win.setWidth(w)
            win.setHeight(h)
            win.setX(int(s.value("window/x")))
            win.setY(int(s.value("window/y")))

        # Defer so the window finishes de-fullscreening before we resize it.
        QTimer.singleShot(50, _do)


# ── main ───────────────────────────────────────────────────────────────────

_HELP = f"""\
picture-show3 {APP_VERSION} - full-screen photo slideshow

Usage:
  python main.py [options] [<picture_dir>]
  python main.py --kiosk [options] <picture_dir>

Arguments:
  <picture_dir>   Path to a folder containing images to display.
                  Supported formats: jpg jpeg png gif bmp webp tiff tif heic avif

Mode options:
  --kiosk         Kiosk mode - the settings page is never shown.
                  Esc opens a quit confirmation dialog instead of going to settings.
                  Exits with an error if the folder contains no supported images.

Show options (session-only — never written to the settings file):
  --autoplay [N]       Enable autoplay; optionally set the interval to N seconds.
                       Without N the last saved interval is kept. Any positive integer
                       is accepted (e.g. --autoplay 6000 waits 6000 seconds).
  --transition T       Set the transition style: fade | slide | zoom | fadeblack
  --transition-dur MS  Set the transition duration in milliseconds (100–3000).
  --sort S             Set the sort order: name | date | random
  --scale MODE         Set the image scale mode: fit | fill
  --auto-panorama      Enable automatic panorama sweep for wide images during autoplay.
  --no-auto-panorama   Disable automatic panorama sweep.
  --recursive          Enable recursive subfolder scanning.
  --loop               Enable looping at the end of the show.
  --no-loop            Disable looping.
  --fullscreen         Start in fullscreen regardless of the last saved window state.

General:
  --help, -h      Show this help message and exit.

Modes:
  Normal          Starts with the settings page. The last used folder is
                  restored from history.

  Jump-start      Loads <picture_dir> and launches the slideshow immediately.
                  Esc during the show returns to the settings page.
                  Folder history is updated normally.

  Kiosk           Designed for unattended display installations.
                  Loads <picture_dir> and launches the slideshow immediately.
                  Esc opens a quit dialog - the settings page is not accessible.
                  Folder history is not updated.

Examples:
  python main.py
  python main.py "C:\\Users\\me\\Pictures\\Vacation"
  python main.py --autoplay 5 --transition slide --fullscreen /mnt/photos
  python main.py --sort date --scale fill --transition-dur 400 /mnt/photos
  python main.py --kiosk --recursive --loop --auto-panorama /mnt/photos

Full CLI reference: docs/cli.md
"""


def _parse_args() -> tuple[str | None, str | None, bool, dict, list[str]]:
    """
    Parse CLI arguments.

    Returns (kiosk_folder, start_folder, force_fullscreen, overrides, qt_argv).

    overrides  – dict of settings to write to QSettings before the controller
                 reads them: keys match QSettings keys ('autoplay', 'interval',
                 'transition', 'recursive', 'loop').
    qt_argv    – cleaned sys.argv passed to QGuiApplication (unknown flags
                 forwarded so Qt's own flag handling still works).
    """
    import argparse

    parser = argparse.ArgumentParser(prog="picture-show3", add_help=False)
    parser.add_argument("folder", nargs="?", default=None, metavar="picture_dir")
    parser.add_argument("--kiosk",      action="store_true", default=False)
    parser.add_argument("--help", "-h", action="store_true")
    parser.add_argument(
        "--autoplay", nargs="?", const=-1, type=int, metavar="SECONDS",
        help="Enable autoplay; optionally set interval in seconds (1–99)",
    )
    parser.add_argument(
        "--transition", choices=["fade", "slide", "zoom", "fadeblack"], default=None,
    )
    parser.add_argument(
        "--transition-dur", type=int, metavar="MS", default=None,
    )
    parser.add_argument(
        "--sort", choices=["name", "date", "random"], default=None,
    )
    parser.add_argument(
        "--scale", choices=["fit", "fill"], default=None,
    )
    parser.add_argument("--auto-panorama", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--recursive",     action="store_true", default=False)
    parser.add_argument("--loop",          action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--fullscreen",    action="store_true", default=False)

    args, remaining = parser.parse_known_args(sys.argv[1:])

    if args.help:
        print(_HELP, end="")
        sys.exit(0)

    kiosk_folder: str | None = args.folder if args.kiosk else None
    start_folder: str | None = args.folder if not args.kiosk else None

    overrides: dict = {}
    if args.autoplay is not None:
        overrides["autoplay"] = True
        if args.autoplay > 0:
            overrides["interval"] = args.autoplay * 1000
    if args.transition is not None:
        overrides["transition"] = args.transition
    if args.transition_dur is not None:
        overrides["transitionDuration"] = args.transition_dur
    if args.sort is not None:
        overrides["sort"] = args.sort
    if args.scale is not None:
        overrides["imageFill"] = (args.scale == "fill")
    if args.auto_panorama is not None:
        overrides["autoPanorama"] = args.auto_panorama
    if args.recursive:
        overrides["recursive"] = True
    if args.loop is not None:
        overrides["loop"] = args.loop

    qt_argv = [sys.argv[0]] + remaining
    return kiosk_folder, start_folder, args.fullscreen, overrides, qt_argv


def main() -> None:
    # Apply UI scale factor before QGuiApplication is created (QT_SCALE_FACTOR
    # is read only at application startup, so it must be set here).
    _apply_ui_scale()

    # Use INI file for settings so they're human-readable
    # Location: %APPDATA%\picture-show3\picture-show3.ini  (Windows)
    QSettings.setDefaultFormat(QSettings.Format.IniFormat)

    # Force a non-native style so custom Slider background/handle work on all platforms
    QQuickStyle.setStyle("Basic")

    kiosk_folder, start_folder, force_fullscreen, overrides, argv = _parse_args()
    if kiosk_folder is not None and not Path(kiosk_folder).is_dir():
        print(f"Error: kiosk folder does not exist: {kiosk_folder}", file=sys.stderr)
        sys.exit(1)
    if start_folder is not None and not Path(start_folder).is_dir():
        print(f"Error: folder does not exist: {start_folder}", file=sys.stderr)
        sys.exit(1)

    QImageReader.setAllocationLimit(1024)
    app = QGuiApplication(argv)
    app.setApplicationName("picture-show3")
    app.setOrganizationName("picture-show3")

    app.translator = _install_translator(app)   # None if no matching .qm found
    if _FROZEN:
        app.setWindowIcon(QIcon(":/img/icon.svg"))
    else:
        ico = _base_dir() / "img" / "icon.ico"
        svg = _base_dir() / "img" / "icon.svg"
        app.setWindowIcon(QIcon(str(ico if ico.exists() else svg)))

    engine = QQmlApplicationEngine()

    # Store on app so Python's GC never collects them while QML holds references
    app.controller     = SlideshowController(
                             kiosk_mode=kiosk_folder is not None,
                             jump_start=start_folder is not None,
                         )
    # Apply CLI overrides after controller init so they shadow the saved settings
    # for this session only — the INI file is never modified.
    if overrides:
        app.controller.apply_cli_overrides(overrides)
    app.provider       = SlideshowImageProvider(app.controller)
    app.qr_provider    = QrImageProvider()
    app.remote         = RemoteServer(app.controller, port=app.controller.remotePort, version=APP_VERSION)
    app.window_helper  = WindowHelper()
    app.update_checker = UpdateChecker()

    engine.addImageProvider("slides", app.provider)
    engine.addImageProvider("qr",     app.qr_provider)
    ctx = engine.rootContext()
    ctx.setContextProperty("controller",    app.controller)
    ctx.setContextProperty("remoteServer",  app.remote)
    ctx.setContextProperty("windowHelper",  app.window_helper)
    ctx.setContextProperty("updateChecker", app.update_checker)
    ctx.setContextProperty("appVersion",    APP_VERSION)

    if kiosk_folder:
        app.controller.loadFolder(kiosk_folder)
        # Connect AFTER loadFolder so the initial image-clear signal is not seen.
        # When the background scan finishes with no usable images, quit with an error.
        def _kiosk_no_images():
            if not app.controller.scanning and app.controller.imageCount == 0:
                print(f"Error: no supported images found in: {kiosk_folder}", file=sys.stderr)
                app.quit()
        app.controller.imagesChanged.connect(_kiosk_no_images)
    elif start_folder:
        app.controller.loadFolder(start_folder)

    engine.load(_QML_ROOT)

    if not engine.rootObjects():
        sys.exit(-1)

    win = engine.rootObjects()[0]
    app.window_helper.set_window(win)
    _restore_window(win, force_fullscreen=force_fullscreen)
    app.aboutToQuit.connect(app.controller.cancelAll)
    app.aboutToQuit.connect(lambda: _save_window(win, app.window_helper))

    if app.controller.updateCheckEnabled:
        QTimer.singleShot(3000, lambda: app.update_checker.check(APP_VERSION))

    sys.exit(app.exec())


def _find_target_screen(s: QSettings):
    """
    Return the QScreen the window should be restored to, or None.

    Strategy (in order):
    1. Match by saved screen name  ('window/screen' key) - exact identity.
    2. Match by geometry: find the screen whose geometry contains the saved
       windowed x/y - handles renames or missing name key.
    """
    screens = QGuiApplication.screens()
    screen_name = s.value("window/screen", "")
    if screen_name:
        for screen in screens:
            if screen.name() == screen_name:
                return screen
    # Geometry-based fallback
    if s.contains("window/x"):
        x = int(s.value("window/x"))
        y = int(s.value("window/y"))
        for screen in screens:
            if screen.geometry().contains(x, y):
                return screen
    return None


def _restore_window(win, force_fullscreen: bool = False) -> None:
    s = QSettings()
    if s.contains("window/width"):
        avail = QGuiApplication.primaryScreen().availableGeometry()
        w = min(int(s.value("window/width")),  avail.width())
        h = min(int(s.value("window/height")), avail.height())
        win.setWidth(w)
        win.setHeight(h)
    if s.contains("window/x"):
        win.setX(int(s.value("window/x")))
        win.setY(int(s.value("window/y")))
    if force_fullscreen or s.value("window/fullscreen", False, type=bool):
        # Do NOT call saveWindowed() here - the windowed geometry in settings
        # is already correct and must not be overwritten with fullscreen dims.
        if sys.platform == "linux":
            # On X11/Wayland the WM is a separate process.  visibilityChanged
            # fires before the X server sends MapNotify and before the WM has
            # actually managed the window, so showFullScreen() still arrives too
            # early via that signal.  activeChanged fires only after the WM
            # grants focus - the window is fully mapped at that point.
            #
            # Additionally, setX/setY before show() are only position *hints* on
            # X11 and are ignored entirely on Wayland.  We must use setScreen()
            # to guarantee the fullscreen lands on the correct monitor.
            def _on_active() -> None:
                if win.isActive():
                    win.activeChanged.disconnect(_on_active)
                    target = _find_target_screen(s)
                    if target is not None and target is not win.screen():
                        win.setScreen(target)
                    win.showFullScreen()
            win.activeChanged.connect(_on_active)
            QTimer.singleShot(0, win.show)
        else:
            # On Windows the kernel manages windows directly - showFullScreen()
            # is honored immediately even before the window is visible.
            QTimer.singleShot(0, win.showFullScreen)
    else:
        # Defer show() to the first event loop iteration (same pattern as above).
        # Calling win.show() before app.exec() starts leaves the native window surface
        # visible for several frames before Qt Quick's render loop fires - causing a white flash.
        if sys.platform == "linux":
            # Call setScreen() *before* show() so the native surface is created
            # on the correct output from the start.  On Wayland the compositor
            # decides final placement, but associating the QWindow with the right
            # QScreen before the surface exists gives it the best chance of landing
            # on the correct monitor.  On X11 this also helps; we additionally
            # re-apply the saved x/y in activeChanged once the WM has mapped the
            # window, which X11 WMs are more likely to honor at that point.
            target = _find_target_screen(s)
            if target is not None and target is not win.screen():
                win.setScreen(target)
            if s.contains("window/x"):
                def _on_active_windowed() -> None:
                    if win.isActive():
                        win.activeChanged.disconnect(_on_active_windowed)
                        win.setX(int(s.value("window/x")))
                        win.setY(int(s.value("window/y")))
                win.activeChanged.connect(_on_active_windowed)
        QTimer.singleShot(0, win.show)


def _save_window(win, helper: WindowHelper) -> None:
    # Freeze helper first so that any visibility change Qt fires during the
    # close sequence does not flip our tracked state.
    helper.freeze()

    s = QSettings()
    is_fullscreen = helper.is_fullscreen
    s.setValue("window/fullscreen", is_fullscreen)
    # Always persist the screen name so restore can target the right monitor.
    if win.screen() is not None:
        s.setValue("window/screen", win.screen().name())
    if not is_fullscreen:
        # Windowed: persist current geometry.
        s.setValue("window/width",  win.width())
        s.setValue("window/height", win.height())
        s.setValue("window/x",      win.x())
        s.setValue("window/y",      win.y())
    # Fullscreen: windowed geometry was already saved by saveWindowed() when
    # we entered fullscreen, so we leave it untouched.


if __name__ == "__main__":
    main()
