# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
SlideshowController — QObject exposed to QML via context property.
Manages image list, current index, sorting, playback timer, and settings.

Requires Python >= 3.14
"""
from __future__ import annotations

import os
import re
import random
import struct
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import xml.etree.ElementTree as ET

from PIL import Image, IptcImagePlugin, UnidentifiedImageError

# Allow very large images (e.g. high-res panoramas) without a decompression bomb warning
Image.MAX_IMAGE_PIXELS = 500_000_000
from PySide6.QtCore import Property, QLocale, QObject, QSettings, QTimer, Signal, Slot

# EXIF tag ids
_EXIF_DATE_TAKEN       = 36867   # DateTimeOriginal
_EXIF_MAKE             = 271
_EXIF_MODEL            = 272
_EXIF_EXPOSURE_TIME    = 33434
_EXIF_FNUMBER          = 33437
_EXIF_EXPOSURE_PROGRAM = 34850
_EXIF_ISO              = 34855
_EXIF_FLASH            = 37385
_EXIF_FOCAL_LENGTH     = 37386
_EXIF_PIXEL_X          = 40962
_EXIF_PIXEL_Y          = 40963


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
    scanProgressChanged = Signal()
    ratingWritten       = Signal(int)    # emitted with image index after a successful write
    # Private: background thread → main thread handoffs
    _scanComplete       = Signal(object, int)   # (result dict | None, generation)
    _sortComplete       = Signal(object, int)   # (sorted all_images list, generation)
    _ratingsComplete    = Signal(object, int)   # (rating_cache dict, generation)
    _progressUpdate     = Signal(int)           # files processed so far

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
        self._exif_cache      : tuple[int, list] = (-1, [])  # (index, rows)
        self._language        : str              = "auto"
        self._update_check_enabled: bool         = True
        self._recursive           : bool         = False
        self._scan_generation     : int          = 0
        self._scanning            : bool         = False
        self._scan_phase          : str          = ""   # "scan", "sort", "filter"
        self._scan_progress       : int          = 0   # files processed (metadata phase only)
        self._cancel_event        : threading.Event = threading.Event()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.nextImage)
        self._scanComplete.connect(self._on_scan_complete)
        self._sortComplete.connect(self._on_sort_complete)
        self._ratingsComplete.connect(self._on_ratings_complete)
        self._progressUpdate.connect(self._on_progress_update)

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
            # Mark scanning immediately so QML shows the scanning state from the
            # first frame, but defer the actual thread start so the window can
            # render before any network I/O begins.
            self._scanning = True
            self._scan_phase = "scan"
            QTimer.singleShot(0, self._scan_images)

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

    @Property(str, notify=scanningChanged)
    def scanPhase(self) -> str: return self._scan_phase

    @Property(int, notify=scanProgressChanged)
    def scanProgress(self) -> int: return self._scan_progress

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
            self._exif_cache = (-1, [])
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
        self._exif_cache = (-1, [])
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

    @Slot(str)
    def removeFolderHistory(self, path: str) -> None:
        if path in self._folder_history:
            self._folder_history.remove(path)
            self._save_settings()
            self.folderHistoryChanged.emit()

    def _cancel_and_new_event(self) -> threading.Event:
        """Signal the running worker to stop and return a fresh cancel event."""
        self._cancel_event.set()
        self._cancel_event = threading.Event()
        return self._cancel_event

    @Slot()
    def cancelAll(self) -> None:
        """Cancel any running background workers.  Call on app quit."""
        self._cancel_event.set()

    def _scan_images(self) -> None:
        """Start a background scan.  Discovery → sort → ratings pipeline."""
        cancel = self._cancel_and_new_event()
        self._scanning = True
        self._scan_phase = "scan"
        self.scanningChanged.emit()
        self._scan_generation += 1
        threading.Thread(
            target=self._scan_worker,
            args=(self._folder, self._recursive, self._scan_generation, cancel),
            daemon=True,
        ).start()

    def _scan_worker(self, folder_path: str, recursive: bool, gen: int,
                     cancel: threading.Event) -> None:
        """Discover image files only — sorting happens in _on_scan_complete."""
        folder = Path(folder_path)
        if not folder.is_dir():
            self._scanComplete.emit(None, gen)
            return
        # os.scandir avoids extra stat calls vs rglob
        all_images: list[str] = []
        if recursive:
            stack = [str(folder)]
            while stack:
                if cancel.is_set():
                    return
                current = stack.pop()
                try:
                    with os.scandir(current) as it:
                        for entry in it:
                            if cancel.is_set():
                                return
                            if entry.is_dir(follow_symlinks=False):
                                stack.append(entry.path)
                            elif entry.is_file(follow_symlinks=False):
                                if Path(entry.name).suffix.lower() in IMAGE_EXTENSIONS:
                                    all_images.append(entry.path)
                except PermissionError:
                    pass
        else:
            try:
                with os.scandir(str(folder)) as it:
                    for entry in it:
                        if cancel.is_set():
                            return
                        if entry.is_file(follow_symlinks=False):
                            if Path(entry.name).suffix.lower() in IMAGE_EXTENSIONS:
                                all_images.append(entry.path)
            except PermissionError:
                pass
        self._scanComplete.emit({"all": all_images}, gen)

    def _parallel_date_sort(self, images: list[str], cancel: threading.Event,
                            max_workers: int = 8,
                            report_progress: bool = False) -> list[str] | None:
        """Sort images by EXIF date using parallel reads.  Returns None if cancelled."""
        keyed: list[tuple[datetime, str]] = []
        done = 0
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(SlideshowController._date_key, p): p for p in images}
            for future in futures:
                # Poll with short timeout so cancel checks happen frequently
                while True:
                    if cancel.is_set():
                        pool.shutdown(wait=False, cancel_futures=True)
                        return None
                    try:
                        dt = future.result(timeout=0.1)
                        break
                    except TimeoutError:
                        continue
                    except Exception:
                        dt = datetime.min
                        break
                keyed.append((dt, futures[future]))
                if report_progress:
                    done += 1
                    self._progressUpdate.emit(done)
        keyed.sort()
        return [p for _, p in keyed]

    @Slot(object, int)
    def _on_scan_complete(self, result, gen: int) -> None:
        if gen != self._scan_generation:
            return  # stale — a newer scan is already running
        if result is None:
            self.errorOccurred.emit(self.tr("Folder not found: {}").format(self._folder))
            self._all_images = []
            self._images = []
            self._rating_cache = {}
            self._exif_cache = (-1, [])
            self._scanning = False
            self.scanningChanged.emit()
            self._apply_filter()
            return
        self._all_images = result["all"]
        # Chain into sort — don't emit signals yet, the pipeline end will.
        self._sort_in_background()

    def _sort_in_background(self) -> None:
        """Re-sort already-loaded images in a background thread.
        Stays in scanning state — caller must already have _scanning=True."""
        cancel = self._cancel_and_new_event()
        if not self._scanning:
            self._scanning = True
        self._scan_phase = "sort"
        self.scanningChanged.emit()
        # Reset progress — only shown during metadata phases (date sort / ratings)
        if self._scan_progress != 0:
            self._scan_progress = 0
            self.scanProgressChanged.emit()
        self._scan_generation += 1
        threading.Thread(
            target=self._sort_worker,
            args=(list(self._all_images), self._sort_order, self._scan_generation, cancel),
            daemon=True,
        ).start()

    def _sort_worker(self, images: list[str], sort_order: str, gen: int,
                     cancel: threading.Event) -> None:
        match sort_order:
            case "name":
                images.sort(key=lambda p: Path(p).name.lower())
            case "date":
                images = self._parallel_date_sort(images, cancel, report_progress=True)
                if images is None:
                    return  # cancelled
            case "random":
                random.shuffle(images)
        if not cancel.is_set():
            self._sortComplete.emit({"images": images, "order": sort_order}, gen)

    @Slot(object, int)
    def _on_sort_complete(self, result, gen: int) -> None:
        if gen != self._scan_generation:
            return
        self._all_images = result["images"]
        # If the user changed sort order while we were sorting, re-sort
        if result["order"] != self._sort_order:
            self._sort_in_background()
            return
        # Chain into ratings read if star filter is active and cache is empty
        if self._min_rating > 0 and not self._rating_cache:
            self._read_ratings_in_background()
        else:
            self._scanning = False
            self._scan_progress = 0
            self.scanningChanged.emit()
            self.scanProgressChanged.emit()
            self._apply_filter()   # emit signals only at pipeline end

    # ── Lazy rating reads ──────────────────────────────────────────────────────

    def _read_ratings_in_background(self) -> None:
        """Read XMP ratings for all images in parallel background threads.
        Stays in scanning state — caller must already have _scanning=True."""
        cancel = self._cancel_and_new_event()
        if not self._scanning:
            self._scanning = True
        self._scan_phase = "filter"
        self.scanningChanged.emit()
        self._scan_progress = 0
        self.scanProgressChanged.emit()
        self._scan_generation += 1
        threading.Thread(
            target=self._ratings_worker,
            args=(list(self._all_images), self._scan_generation, cancel),
            daemon=True,
        ).start()

    def _ratings_worker(self, images: list[str], gen: int,
                        cancel: threading.Event) -> None:
        rating_cache: dict[str, int] = {}
        done = 0
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = {pool.submit(SlideshowController._read_xmp_rating, p): p
                       for p in images}
            total = len(futures)
            for future in futures:
                # Poll with short timeout so cancel checks happen frequently
                while True:
                    if cancel.is_set():
                        pool.shutdown(wait=False, cancel_futures=True)
                        return
                    try:
                        rating = future.result(timeout=0.1)
                        break
                    except TimeoutError:
                        continue
                    except Exception:
                        rating = 0
                        break
                rating_cache[futures[future]] = rating
                done += 1
                self._progressUpdate.emit(done)
        if not cancel.is_set():
            self._ratingsComplete.emit(rating_cache, gen)

    @Slot(object, int)
    def _on_ratings_complete(self, rating_cache: dict[str, int], gen: int) -> None:
        if gen != self._scan_generation:
            return
        self._rating_cache = rating_cache
        self._scanning = False
        self._scan_progress = 0
        self.scanningChanged.emit()
        self.scanProgressChanged.emit()
        self._apply_filter()   # re-apply with real ratings

    @Slot(int)
    def _on_progress_update(self, done: int) -> None:
        self._scan_progress = done
        self.scanProgressChanged.emit()

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
            # Cancel any running sort/ratings and re-sort immediately.
            # During scan phase _all_images is empty, so we just save and
            # the pipeline will use the current _sort_order after discovery.
            self._sort_in_background()
        self._save_settings()
        self.settingsChanged.emit()

    @Slot(int)
    def setMinRating(self, rating: int) -> None:
        clamped = max(0, min(5, rating))
        if clamped == self._min_rating:
            return
        self._min_rating = clamped
        if self._all_images:
            # Cancel any running sort/ratings and re-apply.
            # During scan phase _all_images is empty, so we just save and
            # the pipeline will use the current _min_rating after discovery.
            if clamped > 0 and not self._rating_cache:
                self._read_ratings_in_background()
            else:
                # If a sort/ratings worker was running, cancel it
                if self._scanning:
                    self._cancel_event.set()
                    self._scanning = False
                    self.scanningChanged.emit()
                self._apply_filter()
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

    def _exposure_program_str(self, code: int) -> str:
        programs = {
            0: self.tr("Not defined"),
            1: self.tr("Manual"),
            2: self.tr("Auto"),
            3: self.tr("Aperture priority"),
            4: self.tr("Shutter priority"),
            5: self.tr("Creative"),
            6: self.tr("Action"),
            7: self.tr("Portrait"),
            8: self.tr("Landscape"),
        }
        return programs.get(code, str(code))

    @Slot(int, result='QVariantList')
    def imageExifInfo(self, index: int) -> list:
        """Return a list of {label, value} dicts with EXIF metadata for QML display."""
        if self._exif_cache[0] == index:
            return self._exif_cache[1]
        path = self.imagePath(index)
        if not path:
            return []
        rows: list[dict] = []
        try:
            with Image.open(path) as img:
                pil_w, pil_h = img.size
                try:
                    exif = img._getexif() or {}
                except Exception:
                    exif = {}
        except Exception:
            return []

        # Camera (Manufacturer + Model)
        make  = str(exif.get(_EXIF_MAKE,  "") or "").strip()
        model = str(exif.get(_EXIF_MODEL, "") or "").strip()
        if make or model:
            # Avoid "Canon Canon EOS R5" when model string already starts with make
            camera = model if model.startswith(make) else f"{make} {model}".strip()
            rows.append({"label": self.tr("Camera"), "value": camera})

        # Aperture (F-number)
        fnumber = exif.get(_EXIF_FNUMBER)
        if fnumber is not None:
            try:
                f = float(fnumber)
                rows.append({"label": self.tr("Aperture"), "value": f"f/{f:.1f}"})
            except Exception:
                pass

        # Shutter speed (Exposure time)
        exp_time = exif.get(_EXIF_EXPOSURE_TIME)
        if exp_time is not None:
            try:
                f = float(exp_time)
                if f > 0:
                    if f < 1.0:
                        rows.append({"label": self.tr("Shutter"), "value": f"1/{round(1 / f)} s"})
                    else:
                        rows.append({"label": self.tr("Shutter"), "value": f"{f:.1f} s"})
            except Exception:
                pass

        # ISO
        iso = exif.get(_EXIF_ISO)
        if iso is not None:
            if isinstance(iso, (list, tuple)):
                iso = iso[0] if iso else None
            if iso is not None:
                rows.append({"label": self.tr("ISO"), "value": str(iso)})

        # Focal length
        fl = exif.get(_EXIF_FOCAL_LENGTH)
        if fl is not None:
            try:
                f = float(fl)
                val = f"{f:.0f}" if f == int(f) else f"{f:.1f}"
                rows.append({"label": self.tr("Focal length"), "value": f"{val} mm"})
            except Exception:
                pass

        # Exposure program
        ep = exif.get(_EXIF_EXPOSURE_PROGRAM)
        if ep is not None:
            rows.append({"label": self.tr("Exposure"), "value": self._exposure_program_str(ep)})

        # Flash
        flash = exif.get(_EXIF_FLASH)
        if flash is not None:
            try:
                rows.append({"label": self.tr("Flash"), "value": self.tr("Fired") if (int(flash) & 0x01) else self.tr("Did not fire")})
            except Exception:
                pass

        # Dimensions — prefer EXIF compressed-image size tags, fall back to PIL
        px = exif.get(_EXIF_PIXEL_X, pil_w)
        py = exif.get(_EXIF_PIXEL_Y, pil_h)
        try:
            rows.append({"label": self.tr("Dimensions"), "value": f"{int(px)} × {int(py)}"})
        except Exception:
            rows.append({"label": self.tr("Dimensions"), "value": f"{pil_w} × {pil_h}"})

        self._exif_cache = (index, rows)
        return rows

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

    # ── Star rating write ──────────────────────────────────────────────────────

    @Slot(int, int, result=bool)
    def writeImageRating(self, index: int, rating: int) -> bool:
        """
        Write the XMP star rating to the image file at *index*.
        rating 0 removes the rating; 1–5 sets it.
        Returns True on success, False on error (also emits errorOccurred).
        Updates the in-memory rating cache on success and emits ratingWritten(index).
        """
        path = self.imagePath(index)
        if not path:
            return False
        clamped = max(0, min(5, rating))
        try:
            SlideshowController._write_xmp_rating(path, clamped)
        except Exception as exc:
            self.errorOccurred.emit(self.tr("Could not save rating: %1").replace("%1", str(exc)))
            return False
        # Update cache so subsequent reads are consistent without re-reading the file
        self._rating_cache[path] = clamped
        # Invalidate EXIF panel cache for this index (panel may show Rating row)
        if self._exif_cache[0] == index:
            self._exif_cache = (-1, [])
        self.ratingWritten.emit(index)
        return True

    @staticmethod
    def _write_xmp_rating(path: str, rating: int) -> None:
        """
        Atomically write (or remove) the xmp:Rating in a JPEG file.

        Algorithm
        ---------
        1. Read the file as raw bytes.
        2. Walk JPEG APP markers to locate the XMP APP1 segment
           (identified by the ``http://ns.adobe.com/xap/1.0/\\x00`` namespace prefix).
        3. Modify only the XMP XML text — pixel data is never touched.
        4. Write the result to a sibling temp file.
        5. Open the temp file with Pillow to verify structural integrity.
        6. Atomically rename the temp file over the original.

        Raises
        ------
        ValueError  – file is not a JPEG or unsupported format.
        OSError     – I/O failure.
        """
        suffix = Path(path).suffix.lower()
        if suffix not in (".jpg", ".jpeg"):
            raise ValueError(
                f"Star rating writing is only supported for JPEG files (got {suffix!r})"
            )

        _XMP_NS = b"http://ns.adobe.com/xap/1.0/\x00"

        raw = Path(path).read_bytes()
        if not raw.startswith(b"\xff\xd8"):
            raise ValueError(f"Not a valid JPEG file: {path!r}")

        # ── Locate XMP APP1 segment ───────────────────────────────────────────
        xmp_start: int | None = None
        xmp_end:   int | None = None
        i = 2  # skip SOI (FF D8)
        while i + 3 < len(raw):
            if raw[i] != 0xFF:
                break                                    # lost marker sync
            marker_byte = raw[i + 1]
            # Markers without a length word
            if marker_byte == 0xD9:                      # EOI
                break
            if marker_byte == 0xD8 or 0xD0 <= marker_byte <= 0xD7:
                i += 2
                continue
            # All other markers carry a 2-byte big-endian length (includes itself)
            length = struct.unpack(">H", raw[i + 2: i + 4])[0]
            seg_end = i + 2 + length
            if marker_byte == 0xDA:                      # SOS — compressed data follows
                break
            if marker_byte == 0xE1:                      # APP1
                payload_start = i + 4
                if raw[payload_start: payload_start + len(_XMP_NS)] == _XMP_NS:
                    xmp_start = i
                    xmp_end   = seg_end
                    break
            i = seg_end

        # ── Extract current XMP text ──────────────────────────────────────────
        if xmp_start is not None:
            xmp_offset = xmp_start + 4 + len(_XMP_NS)
            xmp_bytes  = raw[xmp_offset: xmp_end]
            try:
                xmp_str = xmp_bytes.decode("utf-8")
            except UnicodeDecodeError:
                xmp_str = xmp_bytes.decode("latin-1")
        else:
            xmp_str = ""

        # ── Modify XMP text ───────────────────────────────────────────────────
        new_xmp_str   = SlideshowController._modify_xmp_rating_str(xmp_str, rating)
        new_xmp_bytes = new_xmp_str.encode("utf-8")

        # ── Reconstruct JPEG ──────────────────────────────────────────────────
        new_payload = _XMP_NS + new_xmp_bytes
        # APP1 segment: FF E1 + 2-byte length (which counts itself) + payload
        new_seg = b"\xff\xe1" + struct.pack(">H", len(new_payload) + 2) + new_payload

        if xmp_start is not None:
            result = raw[:xmp_start] + new_seg + raw[xmp_end:]
        else:
            # No XMP yet — insert immediately after SOI
            result = raw[:2] + new_seg + raw[2:]

        # ── Write atomically ──────────────────────────────────────────────────
        dir_path = Path(path).parent
        tmp_fd, tmp_path = tempfile.mkstemp(suffix=".tmp", dir=str(dir_path))
        try:
            os.write(tmp_fd, result)
            os.close(tmp_fd)
            tmp_fd = -1
            # Structural check — open and immediately close; verify() on a
            # re-opened file (Pillow closes after verify())
            with Image.open(tmp_path) as img:
                img.verify()
            os.replace(tmp_path, path)
        except Exception:
            if tmp_fd >= 0:
                try:
                    os.close(tmp_fd)
                except OSError:
                    pass
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            raise

    @staticmethod
    def _modify_xmp_rating_str(xmp_str: str, rating: int) -> str:
        """
        Return a modified copy of *xmp_str* with ``xmp:Rating`` set to *rating*,
        or removed when *rating* == 0.

        Strategy: strip any existing Rating (both attribute and element forms),
        then — if rating > 0 — inject ``xmp:Rating="N"`` as an attribute on the
        first ``rdf:Description`` element.  This avoids duplicate-entry bugs and
        normalises the serialisation form without affecting non-Rating content.

        When no XMP is present at all and rating > 0, a minimal XMP wrapper is
        created from scratch.
        """
        # Attribute form: xmp:Rating="N" (any namespace prefix before "Rating")
        attr_re = re.compile(r'\b(?:\w+:)?Rating="[^"]*"')
        # Element form: <xmp:Rating ...>N</xmp:Rating> — [^>]* allows inline
        # namespace declarations such as xmlns:xmp="..." on the element itself.
        elem_re = re.compile(r'<(?:\w+:)?Rating[^>]*>[^<]*</(?:\w+:)?Rating>')

        # Step 1 — remove all existing rating occurrences in either form
        xmp_str = attr_re.sub("", xmp_str)
        xmp_str = elem_re.sub("", xmp_str)

        if rating == 0:
            return xmp_str

        r = str(rating)

        # Step 2 — inject as attribute on the first rdf:Description.
        # Lazy [^>]*? so the trailing ` />` or `>` lands in group 2 rather than
        # being swallowed by group 1 (greedy [^>]* eats the `/` in `/>` and
        # produces malformed XML like `/ xmp:Rating="5">`).
        # \s*/?>  covers: `>`, `/>`, ` />` — all valid XML element endings.
        desc_re = re.compile(r'(<rdf:Description\b[^>]*?)(\s*/?>)')
        if desc_re.search(xmp_str):
            # Only add xmlns:xmp if the namespace is no longer declared after
            # the rating strip above (e.g. element-form XMP had xmlns:xmp on
            # the child <xmp:Rating> element that was just removed).
            _XMP_NS_DECL = 'xmlns:xmp="http://ns.adobe.com/xap/1.0/"'
            ns_inject = '' if _XMP_NS_DECL in xmp_str else f' {_XMP_NS_DECL}'
            xmp_str = desc_re.sub(rf'\1{ns_inject} xmp:Rating="{r}"\2', xmp_str, count=1)
        elif xmp_str:
            # XMP exists but no rdf:Description — insert one before </rdf:RDF>
            insert = (
                f'<rdf:Description rdf:about="" '
                f'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
                f'xmp:Rating="{r}"/>'
            )
            if "</rdf:RDF>" in xmp_str:
                xmp_str = xmp_str.replace("</rdf:RDF>", insert + "</rdf:RDF>", 1)
            else:
                xmp_str += insert
        else:
            # No XMP at all — create a minimal wrapper
            xmp_str = (
                '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
                '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
                f'<rdf:Description rdf:about="" '
                f'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
                f'xmp:Rating="{r}"/>'
                '</rdf:RDF>'
                '</x:xmpmeta>'
            )

        return xmp_str
