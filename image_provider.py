# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
SlideshowImageProvider
Serves images to QML via the custom URI scheme  image://slides/<index>
Respects EXIF orientation. Preloads neighbouring images in background threads
so navigation feels instant.

Requires Python >= 3.14
"""
from __future__ import annotations

import threading

from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QGuiApplication, QImage, QImageReader
from PySide6.QtQuick import QQuickImageProvider

# Register HEIC/HEIF support into Pillow if pillow-heif is installed
try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    pass

from slideshow_controller import SlideshowController

# How many images to keep ready on each side of the current index
_AHEAD  = 2
_BEHIND = 1


def _pillow_to_qimage(path: str) -> QImage:
    """Fallback loader using Pillow — handles HEIC, AVIF, and other Qt-unsupported formats."""
    try:
        from PIL import Image, ImageOps
        img = Image.open(path)
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGBA")
        data = img.tobytes()
        qimage = QImage(data, img.width, img.height, QImage.Format.Format_RGBA8888)
        return qimage.copy()  # copy so QImage owns the buffer
    except Exception:
        return QImage()


class SlideshowImageProvider(QQuickImageProvider):
    def __init__(self, controller: SlideshowController) -> None:
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._controller = controller
        self._cache      : dict[int, QImage]         = {}
        self._loading    : set[int]                   = set()
        self._load_events: dict[int, threading.Event] = {}
        self._lock = threading.Lock()

        controller.currentIndexChanged.connect(self._schedule_preload)
        controller.imagesChanged.connect(self._clear_cache)

    # ── Cache management ──────────────────────────────────────────────────────

    def _clear_cache(self) -> None:
        with self._lock:
            self._cache.clear()
            self._loading.clear()
            # Unblock any requestImage calls waiting on in-flight preloads so
            # they fall through to a fresh synchronous load instead of hanging.
            for ev in self._load_events.values():
                ev.set()
            self._load_events.clear()

    def _schedule_preload(self) -> None:
        idx   = self._controller.currentIndex
        total = self._controller.imageCount
        window = set(range(max(0, idx - _BEHIND), min(total, idx + _AHEAD + 1)))

        events: dict[int, threading.Event] = {}
        with self._lock:
            # Evict images that have scrolled out of the window
            for k in list(self._cache.keys()):
                if k not in window:
                    del self._cache[k]
            # Start a thread for each image not yet cached or in-flight
            needed = window - self._cache.keys() - self._loading
            for i in needed:
                self._loading.add(i)
                ev = threading.Event()
                self._load_events[i] = ev
                events[i] = ev

        for i, ev in events.items():
            threading.Thread(target=self._load_into_cache, args=(i, QSize(), ev),
                             daemon=True).start()

    def _load_into_cache(self, index: int, target_size: QSize,
                         done_event: threading.Event) -> None:
        path = self._controller.imagePath(index)
        image = QImage()
        if path:
            reader = QImageReader(path)
            reader.setAutoTransform(True)
            if target_size.isValid() and target_size.width() > 0:
                native = reader.size()
                if native.isValid():
                    scaled = native.scaled(target_size, Qt.AspectRatioMode.KeepAspectRatio)
                    reader.setScaledSize(scaled)
            image = reader.read()
            if image.isNull():
                image = _pillow_to_qimage(path)
        with self._lock:
            self._loading.discard(index)
            self._load_events.pop(index, None)
            if not image.isNull():
                self._cache[index] = image
        done_event.set()

    def warmup(self) -> None:
        """Pre-populate the cache at display resolution during standby.

        Loads at screen size (not full-res) so the first image can be
        texture-uploaded instantly on slow GPU hardware (e.g. Raspberry Pi).
        Called from the main thread when imagesChanged fires in standby.
        """
        screen = QGuiApplication.primaryScreen()
        display_size = screen.size() if screen else QSize()

        idx   = self._controller.currentIndex
        total = self._controller.imageCount
        if total == 0:
            return
        window = set(range(max(0, idx - _BEHIND), min(total, idx + _AHEAD + 1)))

        events: dict[int, threading.Event] = {}
        with self._lock:
            needed = window - self._cache.keys() - self._loading
            for i in needed:
                self._loading.add(i)
                ev = threading.Event()
                self._load_events[i] = ev
                events[i] = ev

        for i, ev in events.items():
            threading.Thread(target=self._load_into_cache, args=(i, display_size, ev),
                             daemon=True).start()

    # ── QQuickImageProvider interface ─────────────────────────────────────────

    # PySide6 expects requestImage to return QImage only (size is ignored in Python bindings)
    def requestImage(self, image_id: str, size: QSize, requestedSize: QSize) -> QImage:
        # Strip optional cache-busting query param e.g. "42?t=1234567890"
        index_str = image_id.split("?")[0]

        try:
            index = int(index_str)
        except ValueError:
            return QImage()

        with self._lock:
            cached = self._cache.get(index)
            event  = self._load_events.get(index)
        if cached is not None:
            return cached

        # A preload thread is in-flight for this index — wait for it rather than
        # starting a duplicate network read.  The event is set when the thread
        # finishes (success or failure) or when _clear_cache invalidates it.
        if event is not None:
            event.wait(timeout=10.0)
            with self._lock:
                cached = self._cache.get(index)
            if cached is not None:
                return cached

        # True cache miss — load synchronously (fast navigation past preload window)
        path = self._controller.imagePath(index)
        if not path:
            return QImage()

        reader = QImageReader(path)
        reader.setAutoTransform(True)   # honour EXIF rotation

        # Downscale inside the decoder — never upscale
        if requestedSize.width() > 0 and requestedSize.height() > 0:
            native = reader.size()
            if native.isValid():
                scaled = native.scaled(
                    requestedSize,
                    Qt.AspectRatioMode.KeepAspectRatio,
                )
                reader.setScaledSize(scaled)

        image = reader.read()
        if image.isNull():
            image = _pillow_to_qimage(path)
        return image if not image.isNull() else QImage()
