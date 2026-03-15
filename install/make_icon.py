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
