# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
UpdateChecker — checks GitHub Releases for a newer version.

Runs in a background daemon thread so the UI is never blocked.
Emits updateAvailable(str) with the latest version tag when a newer
release is found.  All network errors are swallowed silently.
"""
import json
import re
import threading
import urllib.request

from PySide6.QtCore import QObject, Signal

_RELEASES_API = "https://api.github.com/repos/hel800/picture-show3/releases/latest"
_RELEASES_URL = "https://github.com/hel800/picture-show3/releases/latest"


def _version_tuple(v: str) -> tuple[int, ...]:
    """Extract numeric components, e.g. 'v0.9 beta' → (0, 9)."""
    nums = re.findall(r'\d+', v)
    return tuple(int(x) for x in nums[:3]) if nums else (0,)


class UpdateChecker(QObject):
    """
    Exposed to QML as context property 'updateChecker'.

    Call check(current_version) from Python after the window is shown.
    Connect updateAvailable signal in QML to show a notification.
    """

    # Emitted from the background thread — PySide6 queues it to the main thread
    # automatically when the receiver lives in a different thread.
    updateAvailable = Signal(str)   # latest version string, e.g. "1.0"

    def check(self, current_version: str) -> None:
        """Start a background check.  Safe to call multiple times."""
        threading.Thread(
            target=self._fetch,
            args=(current_version,),
            daemon=True,
        ).start()

    def _fetch(self, current_version: str) -> None:
        try:
            req = urllib.request.Request(
                _RELEASES_API,
                headers={
                    "Accept": "application/vnd.github+json",
                    "User-Agent": "picture-show3",
                },
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read())
            tag = data.get("tag_name", "")
            if _version_tuple(tag) > _version_tuple(current_version):
                self.updateAvailable.emit(tag.lstrip("v"))
        except Exception:
            pass
