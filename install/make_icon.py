# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
make_icon.py — convert img/icon.svg to img/icon.ico

Run once before building with PyInstaller:
    python install/make_icon.py

Requires PySide6 (already a project dependency) and Pillow.
"""
import io
import sys
from pathlib import Path

from PIL import Image
from PySide6.QtCore import QBuffer, QIODeviceBase
from PySide6.QtGui import QImage, QPainter
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtWidgets import QApplication

ROOT  = Path(__file__).parent.parent
SIZES = [256, 128, 64, 48, 32, 16]
SRC   = ROOT / "img" / "icon.svg"
DST   = ROOT / "img" / "icon.ico"

app = QApplication(sys.argv)
renderer = QSvgRenderer(str(SRC))

pil_images: list[Image.Image] = []

for size in SIZES:
    qimg = QImage(size, size, QImage.Format.Format_ARGB32)
    qimg.fill(0)                          # transparent background
    painter = QPainter(qimg)
    renderer.render(painter)
    painter.end()

    buf = QBuffer()
    buf.open(QIODeviceBase.OpenModeFlag.WriteOnly)
    qimg.save(buf, "PNG")
    pil_images.append(Image.open(io.BytesIO(bytes(buf.data()))).copy())
    buf.close()

pil_images[0].save(
    DST,
    format="ICO",
    sizes=[(s, s) for s in SIZES],
    append_images=pil_images[1:],
)
print(f"Created {DST}")
