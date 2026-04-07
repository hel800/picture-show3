# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
make_icon.py — convert img/icon.svg to img/icon.png (256×256)

Run once before building with PyInstaller:
    python install/linux/make_icon.py

Requires PySide6 (already a project dependency) and Pillow.
"""
import io
import sys
from pathlib import Path

from PySide6.QtCore import QBuffer, QIODeviceBase
from PySide6.QtGui import QImage, QPainter
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtWidgets import QApplication

ROOT = Path(__file__).parent.parent.parent
SRC  = ROOT / "img" / "icon.svg"
DST  = ROOT / "img" / "icon.png"

app = QApplication(sys.argv)
renderer = QSvgRenderer(str(SRC))

qimg = QImage(256, 256, QImage.Format.Format_ARGB32)
qimg.fill(0)
painter = QPainter(qimg)
renderer.render(painter)
painter.end()

buf = QBuffer()
buf.open(QIODeviceBase.OpenModeFlag.WriteOnly)
qimg.save(buf, "PNG")
buf.close()

DST.write_bytes(bytes(buf.data()))
print(f"Created {DST}")
