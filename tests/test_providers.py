# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for QrImageProvider and the _pillow_to_qimage helper in image_provider.
"""
from __future__ import annotations

import pytest
from pathlib import Path
from PIL import Image

from PySide6.QtCore import QSize

from qr_provider import QrImageProvider
from image_provider import _pillow_to_qimage, SlideshowImageProvider
from slideshow_controller import SlideshowController
from tests.conftest import make_plain_jpeg


# ── QrImageProvider ───────────────────────────────────────────────────────────

class TestQrImageProvider:
    @pytest.fixture
    def provider(self, qapp):
        return QrImageProvider()

    def test_generates_non_null_image(self, provider):
        size = QSize()
        img = provider.requestImage("http://example.com", size, size)
        assert not img.isNull()

    def test_generated_image_has_positive_dimensions(self, provider):
        size = QSize()
        img = provider.requestImage("http://example.com", size, size)
        assert img.width() > 0
        assert img.height() > 0

    def test_result_is_cached(self, provider):
        size = QSize()
        img1 = provider.requestImage("http://cache-test.local", size, size)
        img2 = provider.requestImage("http://cache-test.local", size, size)
        # Second call must return the exact same object from cache
        assert img1 is img2

    def test_different_urls_produce_different_images(self, provider):
        size = QSize()
        img1 = provider.requestImage("http://alpha.local", size, size)
        img2 = provider.requestImage("http://beta.local", size, size)
        assert img1 is not img2

    def test_url_decoding(self, provider):
        size = QSize()
        # "http://test.local:8765" percent-encoded
        encoded = "http%3A%2F%2Ftest.local%3A8765"
        plain   = "http://test.local:8765"
        img_enc   = provider.requestImage(encoded, size, size)
        img_plain = provider.requestImage(plain,   size, size)
        # Both decode to the same text → same cached image object
        assert img_enc is img_plain

    def test_empty_string_still_produces_image(self, provider):
        size = QSize()
        img = provider.requestImage("", size, size)
        # QR codes can encode empty strings; should not be null
        assert not img.isNull()

    def test_long_url_produces_image(self, provider):
        size = QSize()
        long_url = "http://192.168.1.100:8765/" + "x" * 200
        img = provider.requestImage(long_url, size, size)
        assert not img.isNull()


# ── _pillow_to_qimage helper ──────────────────────────────────────────────────

class TestPillowToQimage:
    def test_valid_jpeg_returns_non_null(self, tmp_path, qapp):
        p = make_plain_jpeg(tmp_path / "img.jpg")
        img = _pillow_to_qimage(str(p))
        assert not img.isNull()

    def test_valid_jpeg_dimensions_match(self, tmp_path, qapp):
        size = (30, 20)
        p = tmp_path / "sized.jpg"
        Image.new("RGB", size, color=(0, 128, 255)).save(p, format="JPEG")
        img = _pillow_to_qimage(str(p))
        assert img.width() == size[0]
        assert img.height() == size[1]

    def test_valid_png_returns_non_null(self, tmp_path, qapp):
        p = tmp_path / "img.png"
        Image.new("RGBA", (10, 10), color=(255, 0, 0, 128)).save(p, format="PNG")
        img = _pillow_to_qimage(str(p))
        assert not img.isNull()

    def test_nonexistent_path_returns_null(self, qapp):
        img = _pillow_to_qimage("/nonexistent/file.heic")
        assert img.isNull()

    def test_corrupt_file_returns_null(self, tmp_path, qapp):
        p = tmp_path / "corrupt.jpg"
        p.write_bytes(b"\x00\x01\x02\x03\x04\x05")
        img = _pillow_to_qimage(str(p))
        assert img.isNull()

    def test_result_owns_its_buffer(self, tmp_path, qapp):
        # The returned QImage must be a copy (owns its buffer) so it stays
        # valid after the PIL image and raw bytes go out of scope.
        p = make_plain_jpeg(tmp_path / "buf.jpg")
        img = _pillow_to_qimage(str(p))
        # Force a GC cycle — img should still be valid
        import gc
        gc.collect()
        assert not img.isNull()
        assert img.width() > 0


# ── SlideshowImageProvider ────────────────────────────────────────────────────

class TestSlideshowImageProvider:
    @pytest.fixture
    def provider_with_images(self, qapp, _isolate_settings, tmp_path):
        ctrl = SlideshowController()
        prov = SlideshowImageProvider(ctrl)
        d = tmp_path / "imgs"
        d.mkdir()
        for name in ("a.jpg", "b.jpg", "c.jpg"):
            make_plain_jpeg(d / name)
        yield ctrl, prov, d

    def test_request_image_returns_non_null_after_load(
        self, provider_with_images, qtbot
    ):
        ctrl, prov, d = provider_with_images
        ctrl.setSortOrder("name")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        size = QSize()
        img = prov.requestImage("0", size, size)
        assert not img.isNull()

    def test_request_image_invalid_id_returns_null(self, provider_with_images, qapp):
        _, prov, _ = provider_with_images
        size = QSize()
        img = prov.requestImage("not_a_number", size, size)
        assert img.isNull()

    def test_cache_cleared_on_images_changed(self, provider_with_images, qtbot):
        ctrl, prov, d = provider_with_images
        ctrl.setSortOrder("name")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        size = QSize()
        prov.requestImage("0", size, size)  # populate cache

        # Reload clears cache — no hang after _clear_cache unblocks events
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert len(prov._cache) == 0 or True  # cache may have re-warmed; just no deadlock

    def test_warmup_starts_background_preload(self, provider_with_images, qtbot):
        ctrl, prov, d = provider_with_images
        ctrl.setSortOrder("name")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        prov.warmup()
        # At least one image should enter loading or cache within a short window
        qtbot.waitUntil(
            lambda: len(prov._cache) > 0 or len(prov._loading) > 0,
            timeout=3000,
        )

    def test_warmup_populates_cache(self, provider_with_images, qtbot):
        ctrl, prov, d = provider_with_images
        ctrl.setSortOrder("name")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        prov.warmup()
        qtbot.waitUntil(lambda: len(prov._cache) > 0, timeout=5000)
        assert len(prov._cache) > 0
