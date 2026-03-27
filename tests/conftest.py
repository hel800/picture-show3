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
from PIL.TiffImagePlugin import IFDRational

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


def _inject_app13(jpeg_bytes: bytes, payload: bytes) -> bytes:
    """Insert an APP13 block immediately after the JPEG SOI marker (FF D8)."""
    seg_len = len(payload) + 2          # length field includes itself
    marker = b"\xff\xed" + struct.pack(">H", seg_len) + payload
    return jpeg_bytes[:2] + marker + jpeg_bytes[2:]


def _build_iptc_caption_payload(caption: str) -> bytes:
    """Build a Photoshop 3.0 APP13 payload containing a single IPTC (2,120) record."""
    caption_bytes = caption.encode("utf-8")
    # IPTC record: 0x1c + record(2) + dataset(120=0x78) + 2-byte big-endian length + data
    iptc_record = b"\x1c\x02\x78" + struct.pack(">H", len(caption_bytes)) + caption_bytes
    # 8BIM block: "8BIM" + type 0x0404 + empty pascal name (b"\x00\x00")
    #             + 4-byte data length + IPTC data (padded to even)
    iptc_padded = iptc_record + (b"\x00" if len(iptc_record) % 2 else b"")
    bim_block = b"8BIM\x04\x04\x00\x00" + struct.pack(">I", len(iptc_record)) + iptc_padded
    return b"Photoshop 3.0\x00" + bim_block


def make_jpeg_with_iptc_caption(path: Path, caption: str) -> Path:
    """JPEG with an IPTC Caption/Abstract (2:120) in an APP13 Photoshop 3.0 segment."""
    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="JPEG")
    path.write_bytes(_inject_app13(buf.getvalue(), _build_iptc_caption_payload(caption)))
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


def make_jpeg_with_exif(
    path: Path,
    *,
    make: str = "",
    model: str = "",
    fnumber: tuple[int, int] | None = None,
    exposure_time: tuple[int, int] | None = None,
    iso: int | None = None,
    focal_length: tuple[int, int] | None = None,
    exposure_program: int | None = None,
    flash: int | None = None,
    size: tuple[int, int] = (100, 80),
) -> Path:
    """JPEG with configurable EXIF tags (IFD0 + ExifIFD). All fields optional."""
    img = Image.new("RGB", size)
    exif = img.getexif()
    if make:
        exif[271] = make
    if model:
        exif[272] = model
    exif_ifd: dict = {}
    if fnumber is not None:
        exif_ifd[33437] = IFDRational(*fnumber)
    if exposure_time is not None:
        exif_ifd[33434] = IFDRational(*exposure_time)
    if iso is not None:
        exif_ifd[34855] = iso
    if focal_length is not None:
        exif_ifd[37386] = IFDRational(*focal_length)
    if exposure_program is not None:
        exif_ifd[34850] = exposure_program
    if flash is not None:
        exif_ifd[37385] = flash
    exif_ifd[40962] = size[0]
    exif_ifd[40963] = size[1]
    if exif_ifd:
        exif[0x8769] = exif_ifd
    img.save(path, format="JPEG", exif=exif.tobytes())
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
def load_folder(qtbot):
    """Call loadFolder and wait until the background scan is complete."""
    def _load(ctrl, path):
        ctrl.loadFolder(path)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
    return _load


@pytest.fixture
def ctrl_with_images(ctrl, image_folder, load_folder):
    load_folder(ctrl, str(image_folder))
    return ctrl
