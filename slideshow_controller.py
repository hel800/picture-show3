# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
SlideshowController — QObject exposed to QML via context property.
Manages image list, current index, sorting, playback timer, and settings.

Requires Python >= 3.14
"""
from __future__ import annotations

import os
import random
import sys
import threading
from datetime import datetime
from pathlib import Path

import xml.etree.ElementTree as ET

from PIL import Image, IptcImagePlugin, UnidentifiedImageError

# Allow very large images (e.g. high-res panoramas) without a decompression bomb warning
Image.MAX_IMAGE_PIXELS = 500_000_000
from PySide6.QtCore import Property, QLocale, QObject, QSettings, QTimer, Signal, Slot

# EXIF tag id for DateTimeOriginal (when the shutter was pressed)
_EXIF_DATE_TAKEN = 36867

# Maximum number of recent folders to remember
_MAX_HISTORY = 100

_FROZEN = getattr(sys, "frozen", False)


def _translations_dir() -> Path:
    if _FROZEN:
        return Path(sys._MEIPASS) / "translations"   # type: ignore[attr-defined]
    return Path(__file__).parent / "translations"

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
    scanningChanged     = Signal()
    # Private: background scan thread → main thread handoff
    _scanComplete       = Signal(object, int)   # (result dict | None, generation)

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
        self._remote_enabled  : bool             = False
        self._remote_port     : int              = 8765
        self._all_images      : list[str]        = []
        self._min_rating      : int              = 0
        self._rating_cache    : dict[str, int]   = {}
        self._language        : str              = "auto"
        self._update_check_enabled: bool         = True
        self._recursive           : bool         = False
        self._scan_generation     : int          = 0
        self._scanning            : bool         = False

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.nextImage)
        self._scanComplete.connect(self._on_scan_complete)

        self._load_settings()

    # ── Persistence ───────────────────────────────────────────────────────────
    def _load_settings(self) -> None:
        s = QSettings()
        self._transition_style    = s.value("transition",         "fade")
        self._transition_duration = s.value("transitionDuration", 600, type=int)
        self._hud_size            = s.value("hudSize",            100, type=int)
        self._hud_visible         = s.value("hudVisible",         False, type=bool)
        self._sort_order          = s.value("sort",               "name")
        self._loop             = s.value("loop",          True,  type=bool)
        self._autoplay         = s.value("autoplay",      False, type=bool)
        self._interval         = s.value("interval",      5_000, type=int)
        self._remote_enabled   = s.value("remoteEnabled",   False, type=bool)
        self._remote_port      = s.value("remotePort",     8765,  type=int)
        self._mouse_nav            = s.value("mouseNavEnabled",    False, type=bool)
        self._min_rating           = s.value("minRating",         0,     type=int)
        self._language             = s.value("language",          "auto")
        self._update_check_enabled = s.value("updateCheckEnabled", True,  type=bool)
        self._recursive            = s.value("recursive",          False, type=bool)

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
        s.setValue("autoplay",       self._autoplay)
        s.setValue("interval",       self._interval)
        s.setValue("remoteEnabled",   self._remote_enabled)
        s.setValue("remotePort",      self._remote_port)
        s.setValue("mouseNavEnabled",    self._mouse_nav)
        s.setValue("minRating",          self._min_rating)
        s.setValue("language",           self._language)
        s.setValue("updateCheckEnabled", self._update_check_enabled)
        s.setValue("recursive",          self._recursive)
        s.setValue("folderHistory",      self._folder_history)

    # ── Properties ───────────────────────────────────────────────────────────
    @Property(str, notify=settingsChanged)
    def folder(self) -> str: return self._folder

    @Property(int, notify=imagesChanged)
    def imageCount(self) -> int: return len(self._images)

    @Property(int, notify=imagesChanged)
    def totalImageCount(self) -> int: return len(self._all_images)

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

    @Property(bool, notify=settingsChanged)
    def mouseNavEnabled(self) -> bool: return self._mouse_nav

    @Property(bool, notify=settingsChanged)
    def remoteEnabled(self) -> bool: return self._remote_enabled

    @Property(int, notify=settingsChanged)
    def remotePort(self) -> int: return self._remote_port

    @Property(int, notify=settingsChanged)
    def minRating(self) -> int: return self._min_rating

    @Property(list, notify=folderHistoryChanged)
    def folderHistory(self) -> list[str]: return list(self._folder_history)

    @Property(str, notify=settingsChanged)
    def language(self) -> str: return self._language

    @Property(bool, notify=settingsChanged)
    def updateCheckEnabled(self) -> bool: return self._update_check_enabled

    @Property(bool, notify=settingsChanged)
    def recursiveSearch(self) -> bool: return self._recursive

    @Property(bool, notify=scanningChanged)
    def scanning(self) -> bool: return self._scanning

    @Property(list, notify=settingsChanged)
    def availableLanguages(self) -> list[dict]:
        """
        Return [{code, name}] for the language selector.
        Always includes 'auto' and 'en'; appends any additional languages
        found as compiled .qm files in the translations directory.
        """
        options: list[dict] = [{"code": "auto", "name": "Auto"}]
        seen: set[str] = {"auto", "en"}
        td = _translations_dir()
        if td.is_dir():
            for qm in sorted(td.glob("picture-show3_*.qm")):
                code = qm.stem.removeprefix("picture-show3_")
                if code in seen:
                    continue
                locale = QLocale(code)
                name = locale.nativeLanguageName().capitalize() if locale != QLocale.c() else code
                options.append({"code": code, "name": name})
                seen.add(code)
        options.append({"code": "en", "name": "English"})
        return options

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

        path = path.strip()
        if not path or not Path(path).is_dir():
            self._folder = path
            self._all_images = []
            self._images = []
            self._current_index = 0
            self._rating_cache = {}
            self.imagesChanged.emit()
            self.currentIndexChanged.emit()
            self.settingsChanged.emit()
            return

        self._folder = str(Path(path))
        # Clear immediately so imageCount == 0 during the async scan
        self._all_images = []
        self._images = []
        self._current_index = 0
        self._rating_cache = {}
        self.imagesChanged.emit()
        self.currentIndexChanged.emit()
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
        """Start a background scan.  Results (sorted + filtered) arrive in _on_scan_complete."""
        self._scanning = True
        self.scanningChanged.emit()
        self._scan_generation += 1
        threading.Thread(
            target=self._scan_worker,
            args=(self._folder, self._recursive, self._sort_order, self._scan_generation),
            daemon=True,
        ).start()

    def _scan_worker(self, folder_path: str, recursive: bool, sort_order: str, gen: int) -> None:
        folder = Path(folder_path)
        if not folder.is_dir():
            self._scanComplete.emit(None, gen)
            return
        iterator = folder.rglob("*") if recursive else folder.iterdir()
        all_images = [
            str(f)
            for f in iterator
            if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS
        ]
        # Sort in background — avoids blocking the main thread (date sort reads EXIF)
        match sort_order:
            case "name":
                all_images.sort(key=lambda p: Path(p).name.lower())
            case "date":
                all_images.sort(key=SlideshowController._date_key)
            case "random":
                random.shuffle(all_images)
        # Pre-read all XMP ratings in background so subsequent setMinRating calls
        # are instant (in-memory only, no file I/O on the main thread)
        rating_cache: dict[str, int] = {
            p: SlideshowController._read_xmp_rating(p) for p in all_images
        }
        self._scanComplete.emit({"all": all_images, "ratings": rating_cache}, gen)

    @Slot(object, int)
    def _on_scan_complete(self, result, gen: int) -> None:
        if gen != self._scan_generation:
            return  # stale — a newer scan is already running
        self._scanning = False
        self.scanningChanged.emit()
        if result is None:
            self.errorOccurred.emit(self.tr("Folder not found: {}").format(self._folder))
            self._all_images = []
            self._images = []
            self._rating_cache = {}
        else:
            self._all_images = result["all"]
            self._rating_cache = result["ratings"]
        # Re-apply filter with the *current* _min_rating — the user may have
        # changed it while the background scan was running
        self._apply_filter()   # emits imagesChanged + currentIndexChanged

    def _sort(self, images: list[str]) -> None:
        match self._sort_order:
            case "name":
                images.sort(key=lambda p: Path(p).name.lower())
            case "date":
                images.sort(key=self._date_key)
            case "random":
                random.shuffle(images)

    def _apply_filter(self) -> None:
        if self._min_rating == 0:
            self._images = list(self._all_images)
        else:
            self._images = [
                p for p in self._all_images
                if self._get_cached_rating(p) >= self._min_rating
            ]
        self._current_index = 0
        self.imagesChanged.emit()
        self.currentIndexChanged.emit()

    def _get_cached_rating(self, path: str) -> int:
        if path not in self._rating_cache:
            self._rating_cache[path] = self._read_xmp_rating(path)
        return self._rating_cache[path]

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
        if self._all_images:
            self._sort(self._all_images)
            self._apply_filter()   # emits imagesChanged + currentIndexChanged
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setMinRating(self, rating: int) -> None:
        clamped = max(0, min(5, rating))
        if clamped == self._min_rating:
            return
        self._min_rating = clamped
        self._apply_filter()   # emits imagesChanged + currentIndexChanged
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

    @Slot(bool)
    def setMouseNavEnabled(self, enabled: bool) -> None:
        self._mouse_nav = enabled
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setRemoteEnabled(self, enabled: bool) -> None:
        self._remote_enabled = enabled
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setRemotePort(self, port: int) -> None:
        self._remote_port = port
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setInterval(self, ms: int) -> None:
        self._interval = ms
        self._timer.setInterval(ms)
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(str)
    def setLanguage(self, code: str) -> None:
        self._language = code
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setUpdateCheckEnabled(self, enabled: bool) -> None:
        self._update_check_enabled = enabled
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(bool)
    def setRecursiveSearch(self, enabled: bool) -> None:
        if self._recursive == enabled:
            return
        self._recursive = enabled
        self._save_settings()
        if self._folder:
            self._scan_images()
        self.settingsChanged.emit()

    # ── Playback control ──────────────────────────────────────────────────────
    @Slot()
    def startShow(self) -> None:
        """Called when the show begins — starts the timer if autoplay is on."""
        if self._folder and self._images:
            self._update_history(self._folder)
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
        if self._is_playing:
            self._timer.start()   # restart countdown after any navigation
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
        if self._is_playing:
            self._timer.start()   # restart countdown after any navigation
        self.currentIndexChanged.emit()

    @Slot(int)
    def goTo(self, index: int) -> None:
        if 0 <= index < len(self._images):
            self._current_index = index
            if self._is_playing:
                self._timer.start()   # restart countdown after any navigation
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
    def imageCaption(self, index: int) -> str:
        """Return IPTC Caption/Abstract (tag 2:120), or '' if unavailable."""
        path = self.imagePath(index)
        if not path:
            return ""
        try:
            with Image.open(path) as img:
                iptc = IptcImagePlugin.getiptcinfo(img)
                if iptc:
                    raw = iptc.get((2, 120))
                    if raw:
                        if isinstance(raw, bytes):
                            return raw.decode("utf-8", errors="replace").strip()
                        return str(raw).strip()
        except Exception:
            pass
        return ""

    @Slot(int, result=int)
    def imageRating(self, index: int) -> int:
        """Return XMP Rating (0–5), or 0 if unset or unreadable."""
        path = self.imagePath(index)
        if not path:
            return 0
        return self._get_cached_rating(path)

    @staticmethod
    def _read_xmp_rating(path: str) -> int:
        try:
            with Image.open(path) as img:
                xmp_data = img.info.get("xmp")
            if not xmp_data:
                return 0
            if isinstance(xmp_data, bytes):
                xmp_data = xmp_data.decode("utf-8", errors="replace")
            root = ET.fromstring(xmp_data)
            for elem in root.iter():
                local = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
                if local == "Description":
                    # Rating as attribute: <rdf:Description xmp:Rating="4" ...>
                    for attr, val in elem.attrib.items():
                        if attr.split("}")[-1] == "Rating":
                            return max(0, min(5, int(val)))
                elif local == "Rating":
                    # Rating as element: <xmp:Rating>4</xmp:Rating>
                    if elem.text and elem.text.strip():
                        return max(0, min(5, int(elem.text.strip())))
        except Exception:
            pass
        return 0

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
