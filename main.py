# This file is part of picture-show3.
# Copyright (C) 2026  Sebastian Schäfer
#
# picture-show3 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# picture-show3 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with picture-show3.  If not, see <https://www.gnu.org/licenses/>.
"""
picture-show3 — main entry point
Requires: Python >= 3.14  |  PySide6 >= 6.7
"""
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QSettings, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication, QIcon, QWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from image_provider import SlideshowImageProvider
from qr_provider import QrImageProvider
from remote_server import RemoteServer
from slideshow_controller import SlideshowController

APP_VERSION = "0.2 beta"

_FROZEN = getattr(sys, "frozen", False)


def _base_dir() -> Path:
    """Return the resource root — works from source and when frozen by PyInstaller."""
    if _FROZEN:
        return Path(sys._MEIPASS)          # type: ignore[attr-defined]
    return Path(__file__).parent


# Deployed (frozen): load QML from the compiled Qt resource bundle (qrc:/).
# Dev (source):      load QML from the filesystem for instant edit→run.
if _FROZEN:
    import resources_rc  # noqa: F401  — registers qrc:/ paths with Qt
    _QML_ROOT = QUrl("qrc:/qml/main.qml")
else:
    _QML_ROOT = QUrl.fromLocalFile(str(_base_dir() / "qml" / "main.qml"))


class WindowHelper(QObject):
    """
    Exposed to QML as 'windowHelper'.

    Tracks fullscreen state independently of the OS window state so that
    _save_window() gets reliable values even if Qt mutates the window during
    the close sequence.

    QML contract:
      • Call windowHelper.saveWindowed() immediately before win.showFullScreen()
        (not needed before showNormal() — that is handled automatically).
    """

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._win = None
        self._is_fullscreen = False   # our own authoritative tracking
        self._quitting = False        # set on quit to freeze state

    # ── setup ──────────────────────────────────────────────────────────────

    def set_window(self, win) -> None:
        self._win = win
        win.visibilityChanged.connect(self._on_vis_changed)

    # ── QML-callable slot ──────────────────────────────────────────────────

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

def main() -> None:
    # Use INI file for settings so they're human-readable
    # Location: %APPDATA%\picture-show3\picture-show3.ini  (Windows)
    QSettings.setDefaultFormat(QSettings.Format.IniFormat)

    # Force a non-native style so custom Slider background/handle work on all platforms
    QQuickStyle.setStyle("Basic")

    app = QGuiApplication(sys.argv)
    app.setApplicationName("picture-show3")
    app.setOrganizationName("picture-show3")
    if _FROZEN:
        app.setWindowIcon(QIcon(":/img/icon.svg"))
    else:
        app.setWindowIcon(QIcon(str(_base_dir() / "img" / "icon.svg")))

    engine = QQmlApplicationEngine()

    # Store on app so Python's GC never collects them while QML holds references
    app.controller    = SlideshowController()
    app.provider      = SlideshowImageProvider(app.controller)
    app.qr_provider   = QrImageProvider()
    app.remote        = RemoteServer(app.controller, port=app.controller.remotePort)
    app.window_helper = WindowHelper()

    engine.addImageProvider("slides", app.provider)
    engine.addImageProvider("qr",     app.qr_provider)
    ctx = engine.rootContext()
    ctx.setContextProperty("controller",   app.controller)
    ctx.setContextProperty("remoteServer", app.remote)
    ctx.setContextProperty("windowHelper", app.window_helper)
    ctx.setContextProperty("appVersion",   APP_VERSION)

    engine.load(_QML_ROOT)

    if not engine.rootObjects():
        sys.exit(-1)

    win = engine.rootObjects()[0]
    app.window_helper.set_window(win)
    _restore_window(win)
    app.aboutToQuit.connect(lambda: _save_window(win, app.window_helper))

    sys.exit(app.exec())


def _restore_window(win) -> None:
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
    if s.value("window/fullscreen", False, type=bool):
        # Defer so the window is fully shown before going fullscreen.
        # Do NOT call saveWindowed() here — the windowed geometry in settings
        # is already correct and must not be overwritten with fullscreen dims.
        QTimer.singleShot(0, win.showFullScreen)
    else:
        # Defer show() to the first event loop iteration (same pattern as showFullScreen above).
        # Calling win.show() before app.exec() starts leaves the native window surface
        # visible for several frames before Qt Quick's render loop fires — causing a white flash.
        QTimer.singleShot(0, win.show)


def _save_window(win, helper: WindowHelper) -> None:
    # Freeze helper first so that any visibility change Qt fires during the
    # close sequence does not flip our tracked state.
    helper.freeze()

    s = QSettings()
    is_fullscreen = helper.is_fullscreen
    s.setValue("window/fullscreen", is_fullscreen)
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
