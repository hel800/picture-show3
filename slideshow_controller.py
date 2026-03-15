"""
SlideshowController — QObject exposed to QML via context property.
Manages image list, current index, sorting, playback timer, and settings.

Requires Python >= 3.14
"""
from __future__ import annotations

import os
import random
import sys
from datetime import datetime
from pathlib import Path

from PIL import Image, UnidentifiedImageError
from PySide6.QtCore import Property, QObject, QSettings, QTimer, Signal, Slot

# EXIF tag id for DateTimeOriginal (when the shutter was pressed)
_EXIF_DATE_TAKEN = 36867

# Maximum number of recent folders to remember
_MAX_HISTORY = 10

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------
type SortOrder       = str   # "name" | "date" | "random"
type TransitionStyle = str   # "fade" | "slide" | "zoom" | "dissolve"

IMAGE_EXTENSIONS: frozenset[str] = frozenset(
    {".jpg", ".jpeg", ".png", ".gif", ".bmp",
     ".webp", ".tiff", ".tif", ".heic", ".avif"}
)


class SlideshowController(QObject):
    # ── Signals ──────────────────────────────────────────────────────────────
    imagesChanged       = Signal()
    currentIndexChanged = Signal()
    isPlayingChanged    = Signal()
    settingsChanged     = Signal()
    folderHistoryChanged = Signal()
    errorOccurred       = Signal(str)

    # ── Init ──────────────────────────────────────────────────────────────────
    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._folder          : str              = ""
        self._images          : list[str]        = []
        self._current_index   : int              = 0
        self._is_playing      : bool             = False
        self._transition_style   : TransitionStyle  = "fade"
        self._transition_duration: int            = 600     # milliseconds
        self._hud_size           : int            = 100     # percent (50–200)
        self._hud_visible        : bool           = False
        self._sort_order         : SortOrder      = "name"
        self._loop               : bool           = True
        self._autoplay           : bool           = False
        self._interval           : int            = 5_000   # milliseconds
        self._folder_history  : list[str]        = []

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.nextImage)

        self._load_settings()

    # ── Persistence ───────────────────────────────────────────────────────────
    def _load_settings(self) -> None:
        s = QSettings()
        self._transition_style    = s.value("transition",         "fade")
        self._transition_duration = s.value("transitionDuration", 600, type=int)
        self._hud_size            = s.value("hudSize",            100, type=int)
        self._hud_visible         = s.value("hudVisible",         False, type=bool)
        self._sort_order          = s.value("sort",               "name")
        self._loop             = s.value("loop",       True,  type=bool)
        self._autoplay         = s.value("autoplay",   False, type=bool)
        self._interval         = s.value("interval",   5_000, type=int)

        # QSettings returns a str for single-item lists, list for multiple
        raw = s.value("folderHistory", [])
        match raw:
            case str() if raw:
                self._folder_history = [raw]
            case list():
                self._folder_history = raw
            case _:
                self._folder_history = []

        if self._folder_history:
            self._folder = self._folder_history[0]
            self._scan_images()

    def _save_settings(self) -> None:
        s = QSettings()
        s.setValue("transition",          self._transition_style)
        s.setValue("transitionDuration",  self._transition_duration)
        s.setValue("hudSize",             self._hud_size)
        s.setValue("hudVisible",          self._hud_visible)
        s.setValue("sort",          self._sort_order)
        s.setValue("loop",          self._loop)
        s.setValue("autoplay",      self._autoplay)
        s.setValue("interval",      self._interval)
        s.setValue("folderHistory", self._folder_history)

    # ── Properties ───────────────────────────────────────────────────────────
    @Property(str, notify=settingsChanged)
    def folder(self) -> str: return self._folder

    @Property(int, notify=imagesChanged)
    def imageCount(self) -> int: return len(self._images)

    @Property(int, notify=currentIndexChanged)
    def currentIndex(self) -> int: return self._current_index

    @Property(bool, notify=isPlayingChanged)
    def isPlaying(self) -> bool: return self._is_playing

    @Property(str, notify=settingsChanged)
    def transitionStyle(self) -> TransitionStyle: return self._transition_style

    @Property(int, notify=settingsChanged)
    def transitionDuration(self) -> int: return self._transition_duration

    @Property(int, notify=settingsChanged)
    def hudSize(self) -> int: return self._hud_size

    @Property(bool, notify=settingsChanged)
    def hudVisible(self) -> bool: return self._hud_visible

    @Property(str, notify=settingsChanged)
    def sortOrder(self) -> SortOrder: return self._sort_order

    @Property(bool, notify=settingsChanged)
    def loop(self) -> bool: return self._loop

    @Property(bool, notify=settingsChanged)
    def autoplay(self) -> bool: return self._autoplay

    @Property(int, notify=settingsChanged)
    def interval(self) -> int: return self._interval

    @Property(list, notify=folderHistoryChanged)
    def folderHistory(self) -> list[str]: return list(self._folder_history)

    # ── Folder / image loading ────────────────────────────────────────────────
    @Slot(str)
    def loadFolder(self, folder_path: str) -> None:
        """Accept both plain paths and file:// URLs from QML FolderDialog."""
        match folder_path:
            case p if p.startswith("file:///"):
                path = p[8:] if sys.platform == "win32" else p[7:]
            case p if p.startswith("file://"):
                path = p[7:]
            case _:
                path = folder_path

        self._folder = str(Path(path))
        self._update_history(self._folder)
        self._scan_images()
        self.settingsChanged.emit()

    def _update_history(self, folder: str) -> None:
        if folder in self._folder_history:
            self._folder_history.remove(folder)
        self._folder_history.insert(0, folder)
        self._folder_history = self._folder_history[:_MAX_HISTORY]
        self._save_settings()
        self.folderHistoryChanged.emit()

    @Slot()
    def clearFolderHistory(self) -> None:
        self._folder_history = []
        self._save_settings()
        self.folderHistoryChanged.emit()

    def _scan_images(self) -> None:
        folder = Path(self._folder)
        if not folder.is_dir():
            self.errorOccurred.emit(f"Folder not found: {self._folder!r}")
            images: list[str] = []
        else:
            images = [
                str(f)
                for f in folder.iterdir()
                if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS
            ]

        self._sort(images)
        self._images        = images
        self._current_index = 0
        self.imagesChanged.emit()
        self.currentIndexChanged.emit()

    def _sort(self, images: list[str]) -> None:
        match self._sort_order:
            case "name":
                images.sort(key=lambda p: Path(p).name.lower())
            case "date":
                images.sort(key=self._date_key)
            case "random":
                random.shuffle(images)

    @staticmethod
    def _date_key(path: str) -> datetime:
        """Return DateTimeOriginal from EXIF, falling back to file mtime."""
        try:
            with Image.open(path) as img:
                exif = img._getexif()
                if exif:
                    raw = exif.get(_EXIF_DATE_TAKEN)
                    if raw:
                        return datetime.strptime(raw, "%Y:%m:%d %H:%M:%S")
        except (UnidentifiedImageError, Exception):
            pass
        return datetime.fromtimestamp(os.path.getmtime(path))

    # ── Settings setters (called from QML) ───────────────────────────────────
    @Slot(int)
    def setTransitionDuration(self, ms: int) -> None:
        self._transition_duration = ms
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setHudSize(self, percent: int) -> None:
        self._hud_size = percent
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setHudVisible(self, visible: bool) -> None:
        self._hud_visible = visible
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(str)
    def setTransitionStyle(self, style: TransitionStyle) -> None:
        self._transition_style = style
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(str)
    def setSortOrder(self, order: SortOrder) -> None:
        self._sort_order = order
        if self._images:
            self._sort(self._images)
            self._current_index = 0
            self.imagesChanged.emit()
            self.currentIndexChanged.emit()
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setLoop(self, value: bool) -> None:
        self._loop = value
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setAutoplay(self, value: bool) -> None:
        self._autoplay = value
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setInterval(self, ms: int) -> None:
        self._interval = ms
        self._timer.setInterval(ms)
        self._save_settings()
        self.settingsChanged.emit()

    # ── Playback control ──────────────────────────────────────────────────────
    @Slot()
    def startShow(self) -> None:
        """Called when the show begins — starts the timer if autoplay is on."""
        if self._autoplay and self._images:
            self._timer.setInterval(self._interval)
            self._timer.start()
            self._is_playing = True
            self.isPlayingChanged.emit()

    @Slot()
    def stopShow(self) -> None:
        self._timer.stop()
        self._is_playing = False
        self.isPlayingChanged.emit()

    @Slot()
    def togglePlay(self) -> None:
        match self._is_playing:
            case True:
                self.stopShow()
            case False if self._images:
                self._timer.setInterval(self._interval)
                self._timer.start()
                self._is_playing = True
                self.isPlayingChanged.emit()

    # ── Navigation ────────────────────────────────────────────────────────────
    @Slot()
    def nextImage(self) -> None:
        if not self._images:
            return
        match self._current_index < len(self._images) - 1:
            case True:
                self._current_index += 1
            case False if self._loop:
                self._current_index = 0
            case _:
                self.stopShow()
                return
        self.currentIndexChanged.emit()

    @Slot()
    def prevImage(self) -> None:
        if not self._images:
            return
        match self._current_index > 0:
            case True:
                self._current_index -= 1
            case False if self._loop:
                self._current_index = len(self._images) - 1
            case _:
                return
        self.currentIndexChanged.emit()

    @Slot(int)
    def goTo(self, index: int) -> None:
        if 0 <= index < len(self._images):
            self._current_index = index
            self.currentIndexChanged.emit()

    # ── Image path access (used by ImageProvider and QML) ────────────────────
    @Slot(int, result=str)
    def imagePath(self, index: int) -> str:
        if 0 <= index < len(self._images):
            return self._images[index]
        return ""

    @Slot(result=str)
    def currentImagePath(self) -> str:
        return self.imagePath(self._current_index)

    @Slot(int, result=str)
    def imageDateTaken(self, index: int) -> str:
        """Return EXIF DateTimeOriginal as a readable string, or '' if unavailable."""
        path = self.imagePath(index)
        if not path:
            return ""
        try:
            with Image.open(path) as img:
                exif = img._getexif()
                if exif:
                    raw = exif.get(_EXIF_DATE_TAKEN)
                    if raw:
                        dt = datetime.strptime(raw, "%Y:%m:%d %H:%M:%S")
                        return dt.strftime("%Y-%m-%d  %H:%M")
        except Exception:
            pass
        return ""
