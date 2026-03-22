# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Shared fixtures and image-building helpers for the test suite.
"""
import io
import struct

import pytest
from pathlib import Path
from PIL import Image

from PySide6.QtCore import QSettings


# ── QSettings isolation ───────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def _isolate_settings(tmp_path):
    """
    Redirect QSettings to a fresh per-test temp dir.
    This prevents any _save_settings() call in one test from bleeding
    into the next test's SlideshowController.__init__ → _load_settings().
    """
    d = tmp_path / "_qsettings"
    d.mkdir()
    QSettings.setDefaultFormat(QSettings.Format.IniFormat)
    QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, str(d))


# ── Image-building helpers (plain functions, reusable from tests too) ─────────

def make_plain_jpeg(path: Path, size: tuple[int, int] = (16, 16)) -> Path:
    """Write a minimal JPEG with no metadata."""
    Image.new("RGB", size, color=(100, 150, 200)).save(path, format="JPEG")
    return path


def _inject_app1(jpeg_bytes: bytes, payload: bytes) -> bytes:
    """Insert an APP1 block immediately after the JPEG SOI marker (FF D8)."""
    app1_len = len(payload) + 2          # length field includes itself
    marker = b"\xff\xe1" + struct.pack(">H", app1_len) + payload
    return jpeg_bytes[:2] + marker + jpeg_bytes[2:]


def make_jpeg_with_xmp_attr(path: Path, rating: int) -> Path:
    """JPEG whose XMP carries xmp:Rating as an attribute on rdf:Description."""
    xmp = (
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        f'<rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"'
        f' xmp:Rating="{rating}"/>'
        '</rdf:RDF>'
        '</x:xmpmeta>'
    ).encode("utf-8")
    ns = b"http://ns.adobe.com/xap/1.0/\x00"
    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="JPEG")
    path.write_bytes(_inject_app1(buf.getvalue(), ns + xmp))
    return path


def make_jpeg_with_xmp_elem(path: Path, rating: int) -> Path:
    """JPEG whose XMP carries xmp:Rating as a child element."""
    xmp = (
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="">'
        f'<xmp:Rating xmlns:xmp="http://ns.adobe.com/xap/1.0/">{rating}</xmp:Rating>'
        '</rdf:Description>'
        '</rdf:RDF>'
        '</x:xmpmeta>'
    ).encode("utf-8")
    ns = b"http://ns.adobe.com/xap/1.0/\x00"
    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="JPEG")
    path.write_bytes(_inject_app1(buf.getvalue(), ns + xmp))
    return path


# ── Folder fixtures ───────────────────────────────────────────────────────────

@pytest.fixture
def image_folder(tmp_path):
    """Five plain JPEGs: a.jpg … e.jpg."""
    d = tmp_path / "photos"
    d.mkdir()
    for name in ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"]:
        make_plain_jpeg(d / name)
    return d


@pytest.fixture
def rated_folder(tmp_path):
    """Six JPEGs: r0.jpg has no XMP (rating 0), r1–r5.jpg have xmp:Rating 1–5."""
    d = tmp_path / "rated"
    d.mkdir()
    make_plain_jpeg(d / "r0.jpg")
    for r in range(1, 6):
        make_jpeg_with_xmp_attr(d / f"r{r}.jpg", r)
    return d


# ── Controller fixtures ───────────────────────────────────────────────────────

@pytest.fixture
def ctrl(qapp, _isolate_settings):
    from slideshow_controller import SlideshowController
    return SlideshowController()


@pytest.fixture
def ctrl_with_images(ctrl, image_folder):
    ctrl.loadFolder(str(image_folder))
    return ctrl
