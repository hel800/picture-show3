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
SlideshowImageProvider
Serves images to QML via the custom URI scheme  image://slides/<index>
Respects EXIF orientation. Preloads neighbouring images in background threads
so navigation feels instant.

Requires Python >= 3.14
"""
from __future__ import annotations

import threading
from pathlib import Path

from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QImage, QImageReader
from PySide6.QtQuick import QQuickImageProvider

from slideshow_controller import SlideshowController

# How many images to keep ready on each side of the current index
_AHEAD  = 2
_BEHIND = 1


class SlideshowImageProvider(QQuickImageProvider):
    def __init__(self, controller: SlideshowController) -> None:
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._controller = controller
        self._cache  : dict[int, QImage] = {}
        self._loading: set[int]          = set()
        self._lock = threading.Lock()

        controller.currentIndexChanged.connect(self._schedule_preload)
        controller.imagesChanged.connect(self._clear_cache)

    # ── Cache management ──────────────────────────────────────────────────────

    def _clear_cache(self) -> None:
        with self._lock:
            self._cache.clear()
            self._loading.clear()

    def _schedule_preload(self) -> None:
        idx   = self._controller.currentIndex
        total = self._controller.imageCount
        window = set(range(max(0, idx - _BEHIND), min(total, idx + _AHEAD + 1)))

        with self._lock:
            # Evict images that have scrolled out of the window
            for k in list(self._cache.keys()):
                if k not in window:
                    del self._cache[k]
            # Start a thread for each image not yet cached or in-flight
            needed = window - self._cache.keys() - self._loading
            for i in needed:
                self._loading.add(i)

        for i in needed:
            threading.Thread(target=self._load_into_cache, args=(i,),
                             daemon=True).start()

    def _load_into_cache(self, index: int) -> None:
        path = self._controller.imagePath(index)
        image = QImage()
        if path:
            reader = QImageReader(path)
            reader.setAutoTransform(True)
            image = reader.read()
        with self._lock:
            self._loading.discard(index)
            if not image.isNull():
                self._cache[index] = image

    # ── QQuickImageProvider interface ─────────────────────────────────────────

    # PySide6 expects requestImage to return QImage only (size is ignored in Python bindings)
    def requestImage(self, id: str, size: QSize, requestedSize: QSize) -> QImage:
        # Strip optional cache-busting query param e.g. "42?t=1234567890"
        index_str = id.split("?")[0]

        try:
            index = int(index_str)
        except ValueError:
            return QImage()

        with self._lock:
            cached = self._cache.get(index)
        if cached is not None:
            return cached

        # Cache miss — load synchronously (happens on first image or fast skipping)
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
        return image if not image.isNull() else QImage()
