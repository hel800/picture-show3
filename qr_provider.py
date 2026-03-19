# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
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
