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
QrImageProvider — generates QR code images on demand.
URI scheme:  image://qr/<url-encoded-text>

Example QML usage:
    Image { source: "image://qr/" + encodeURIComponent(remoteServer.url) }
"""
from __future__ import annotations

import io
from urllib.parse import unquote

import qrcode
import qrcode.constants
from PySide6.QtCore import QSize
from PySide6.QtGui import QImage
from PySide6.QtQuick import QQuickImageProvider


class QrImageProvider(QQuickImageProvider):
    def __init__(self) -> None:
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._cache: dict[str, QImage] = {}

    def requestImage(self, id: str, size: QSize, requestedSize: QSize) -> QImage:
        text = unquote(id)

        if text in self._cache:
            return self._cache[text]

        qr = qrcode.QRCode(
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=10,
            border=4,
        )
        qr.add_data(text)
        qr.make(fit=True)
        pil_img = qr.make_image(fill_color="black", back_color="white")

        buf = io.BytesIO()
        pil_img.save(buf, format="PNG")
        buf.seek(0)

        image = QImage()
        image.loadFromData(buf.read())

        self._cache[text] = image
        return image
