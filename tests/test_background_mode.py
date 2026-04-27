# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for _setup_background_mode() — background mode startup behaviour.

Specifically covers the startup stop-hook: on_show_stop must fire at startup
when the show is NOT auto-resuming (showActive=False in settings) so that the
display can be powered off immediately while the process idles in standby.
"""
from __future__ import annotations

import socket
import threading
from unittest.mock import MagicMock, patch

import pytest
from PySide6.QtCore import QObject, QSettings, Signal

from main import _setup_background_mode
from remote_server import RemoteServer
from slideshow_controller import SlideshowController


class _FakeApp(QObject):
    """Minimal QObject stand-in for QGuiApplication inside _setup_background_mode."""

    aboutToQuit = Signal()

    def __init__(self, ctrl: SlideshowController, remote: RemoteServer) -> None:
        super().__init__()
        self.controller = ctrl
        self.remote = remote


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def bg_app(qapp):
    ctrl = SlideshowController()
    srv = RemoteServer(ctrl, port=_free_port(), background_mode=True)
    app = _FakeApp(ctrl, srv)
    yield app
    srv.stop()


class TestAutoplayPersistenceOnStop:
    """_on_stop_show syncs _autoplay from _is_playing so next StartShow restores it."""

    def _win_mock(self):
        win = MagicMock()
        win.screen.return_value = None  # skip the screen-name QSettings write
        return win

    def test_autoplay_preserved_when_playing_at_stop(self, bg_app, qtbot):
        # Precondition: _autoplay False (e.g. CLI override already spent), but show
        # is currently playing.  _on_stop_show must persist the live play state.
        ctrl = bg_app.controller
        ctrl._autoplay = False
        ctrl._is_playing = True
        _setup_background_mode(bg_app, self._win_mock(), False)

        bg_app.remote.stopShowRequested.emit()
        qtbot.wait(50)

        assert ctrl._autoplay is True

    def test_autoplay_false_when_paused_at_stop(self, bg_app, qtbot):
        # If the show was paused when stopped, next StartShow should not autoplay.
        ctrl = bg_app.controller
        ctrl._autoplay = True
        ctrl._is_playing = False
        _setup_background_mode(bg_app, self._win_mock(), False)

        bg_app.remote.stopShowRequested.emit()
        qtbot.wait(50)

        assert ctrl._autoplay is False


class TestStartupStopHook:
    """on_show_stop fires at startup when the show is NOT auto-resuming."""

    def test_hook_fires_when_not_auto_resuming(self, bg_app, qtbot):
        ran = threading.Event()
        with patch("main.subprocess.run", side_effect=lambda *a, **kw: ran.set()) as mock_run:
            _setup_background_mode(
                bg_app, MagicMock(), False, on_show_stop="display_off.sh"
            )
            qtbot.waitUntil(ran.is_set, timeout=3000)
        mock_run.assert_called_once_with("display_off.sh", shell=True)

    def test_hook_not_fired_when_auto_resuming(self, bg_app):
        s = QSettings()
        s.setValue("background_mode/showActive", True)
        s.sync()

        ran = threading.Event()
        with patch("main.subprocess.run", side_effect=lambda *a, **kw: ran.set()):
            _setup_background_mode(
                bg_app, MagicMock(), False, on_show_stop="display_off.sh"
            )
            ran.wait(timeout=0.3)
        assert not ran.is_set()

    def test_no_hook_means_no_subprocess(self, bg_app):
        with patch("main.subprocess.run") as mock_run:
            _setup_background_mode(bg_app, MagicMock(), False, on_show_stop=None)
        mock_run.assert_not_called()
