# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Integration tests for RemoteServer.

The server runs on a free local port; HTTP requests are made from a background
thread while pytest-qt pumps the Qt event loop via qtbot.waitUntil().
"""
from __future__ import annotations

import json
import socket
import threading
import urllib.request
from urllib.error import URLError

import pytest

from remote_server import RemoteServer
from slideshow_controller import SlideshowController
from tests.conftest import make_plain_jpeg


# ── Helpers ───────────────────────────────────────────────────────────────────

def _free_port() -> int:
    """Return an OS-assigned free TCP port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _fetch(url: str, timeout: float = 3.0) -> tuple[int, str]:
    """Blocking HTTP GET; returns (status_code, body_text)."""
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.status, resp.read().decode("utf-8", errors="replace")


def _http_get(qtbot, url: str, timeout_ms: int = 5000) -> tuple[int, str]:
    """
    Fire an HTTP GET in a background thread and pump the Qt event loop until
    the response arrives (or timeout expires).
    """
    result: dict = {}
    done = threading.Event()

    def _worker():
        try:
            result["status"], result["body"] = _fetch(url)
        except Exception as exc:
            result["error"] = str(exc)
        finally:
            done.set()

    threading.Thread(target=_worker, daemon=True).start()
    qtbot.waitUntil(done.is_set, timeout=timeout_ms)
    return result.get("status"), result.get("body", result.get("error", ""))


# ── _local_ip (pure static method — no event loop needed) ────────────────────

class TestLocalIp:
    def test_returns_string(self):
        ip = RemoteServer._local_ip()
        assert isinstance(ip, str)

    def test_looks_like_ipv4(self):
        ip = RemoteServer._local_ip()
        parts = ip.split(".")
        assert len(parts) == 4
        assert all(p.isdigit() for p in parts)

    def test_fallback_on_no_network(self, monkeypatch):
        # Patch socket.socket to raise OSError → should fall back to 127.0.0.1
        import socket as _socket
        original = _socket.socket

        class _FailSocket:
            def __init__(self, *a, **kw):
                raise OSError("simulated failure")

        monkeypatch.setattr(_socket, "socket", _FailSocket)
        assert RemoteServer._local_ip() == "127.0.0.1"


# ── HTTP endpoint tests ───────────────────────────────────────────────────────

@pytest.fixture
def server_and_ctrl(qapp, _isolate_settings, tmp_path):
    """Yield (controller, server, port) with the server already started."""
    ctrl = SlideshowController()
    port = _free_port()
    srv = RemoteServer(ctrl, port=port)
    srv.start()
    yield ctrl, srv, port
    srv.stop()


class TestHttpEndpoints:
    def test_root_returns_html(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        status, body = _http_get(qtbot, f"http://127.0.0.1:{port}/")
        assert status == 200
        assert "<!DOCTYPE html>" in body

    def test_status_returns_json(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        status, body = _http_get(qtbot, f"http://127.0.0.1:{port}/status")
        assert status == 200
        data = json.loads(body)
        assert "index" in data
        assert "total" in data
        assert "playing" in data
        assert "active" in data

    def test_status_initial_values(self, server_and_ctrl, qtbot):
        ctrl, _, port = server_and_ctrl
        _, body = _http_get(qtbot, f"http://127.0.0.1:{port}/status")
        data = json.loads(body)
        assert data["index"] == 0
        assert data["total"] == 0
        assert data["playing"] is False
        assert data["active"] is False

    def test_status_active_flag(self, server_and_ctrl, qtbot):
        ctrl, srv, port = server_and_ctrl
        srv.setShowActive(True)
        _, body = _http_get(qtbot, f"http://127.0.0.1:{port}/status")
        assert json.loads(body)["active"] is True

    def test_next_endpoint(self, server_and_ctrl, tmp_path, qtbot):
        ctrl, _, port = server_and_ctrl
        d = tmp_path / "imgs"
        d.mkdir()
        for n in ("a.jpg", "b.jpg"):
            make_plain_jpeg(d / n)
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        ctrl.setSortOrder("name")
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        ctrl.goTo(0)

        status, body = _http_get(qtbot, f"http://127.0.0.1:{port}/next")
        assert status == 200
        assert body.strip() == "ok"
        assert ctrl.currentIndex == 1

    def test_prev_endpoint(self, server_and_ctrl, tmp_path, qtbot):
        ctrl, _, port = server_and_ctrl
        d = tmp_path / "imgs"
        d.mkdir()
        for n in ("a.jpg", "b.jpg"):
            make_plain_jpeg(d / n)
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        ctrl.setSortOrder("name")
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        ctrl.goTo(1)

        status, body = _http_get(qtbot, f"http://127.0.0.1:{port}/prev")
        assert status == 200
        assert body.strip() == "ok"
        assert ctrl.currentIndex == 0

    def test_toggle_endpoint(self, server_and_ctrl, tmp_path, qtbot):
        ctrl, _, port = server_and_ctrl
        d = tmp_path / "imgs"
        d.mkdir()
        make_plain_jpeg(d / "x.jpg")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        assert ctrl.isPlaying is False
        status, _ = _http_get(qtbot, f"http://127.0.0.1:{port}/toggle")
        assert status == 200
        assert ctrl.isPlaying is True
        ctrl.stopShow()

    def test_toggle_hud_endpoint(self, server_and_ctrl, qtbot):
        ctrl, _, port = server_and_ctrl
        initial = ctrl.hudVisible
        status, _ = _http_get(qtbot, f"http://127.0.0.1:{port}/toggle-hud")
        assert status == 200
        assert ctrl.hudVisible is not initial
        # Toggle back
        _http_get(qtbot, f"http://127.0.0.1:{port}/toggle-hud")
        assert ctrl.hudVisible is initial

    def test_status_includes_hud_visible(self, server_and_ctrl, qtbot):
        ctrl, _, port = server_and_ctrl
        _, body = _http_get(qtbot, f"http://127.0.0.1:{port}/status")
        data = json.loads(body)
        assert "hud_visible" in data
        assert data["hud_visible"] == ctrl.hudVisible

    def test_preview_returns_404_when_no_images(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        assert _http_status(qtbot, f"http://127.0.0.1:{port}/preview") == 404

    def test_preview_returns_jpeg_when_image_loaded(self, server_and_ctrl, tmp_path, qtbot):
        ctrl, _, port = server_and_ctrl
        d = tmp_path / "imgs"
        d.mkdir()
        make_plain_jpeg(d / "a.jpg")
        ctrl.loadFolder(str(d))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        status, body = _http_get(qtbot, f"http://127.0.0.1:{port}/preview")
        assert status == 200
        assert len(body) > 0

    def test_unknown_path_returns_404(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        try:
            _http_get(qtbot, f"http://127.0.0.1:{port}/doesnotexist")
        except Exception:
            pass  # urllib raises HTTPError for 4xx — that's fine

        # Re-fetch with a lower-level approach that doesn't raise on 4xx
        result: dict = {}
        done = threading.Event()

        def _worker():
            try:
                req = urllib.request.Request(
                    f"http://127.0.0.1:{port}/doesnotexist"
                )
                try:
                    urllib.request.urlopen(req, timeout=3)
                except urllib.error.HTTPError as e:
                    result["status"] = e.code
            except Exception as exc:
                result["error"] = str(exc)
            finally:
                done.set()

        threading.Thread(target=_worker, daemon=True).start()
        qtbot.waitUntil(done.is_set, timeout=5000)
        assert result.get("status") == 404

    def test_svg_assets_served(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        for path in ("/logo.svg", "/icon_play.svg", "/icon_pause.svg"):
            status, body = _http_get(qtbot, f"http://127.0.0.1:{port}{path}")
            assert status == 200
            assert "<svg" in body.lower() or "<?xml" in body.lower() or body.startswith("<")


# ── Background mode endpoints ─────────────────────────────────────────────────

def _http_status(qtbot, url: str, timeout_ms: int = 5000) -> int:
    """HTTP GET that returns the status code even for 4xx/5xx responses."""
    result: dict = {}
    done = threading.Event()

    def _worker():
        try:
            urllib.request.urlopen(url, timeout=3)
            result["status"] = 200
        except urllib.error.HTTPError as e:
            result["status"] = e.code
        except Exception as exc:
            result["error"] = str(exc)
        finally:
            done.set()

    threading.Thread(target=_worker, daemon=True).start()
    qtbot.waitUntil(done.is_set, timeout=timeout_ms)
    return result.get("status", -1)


@pytest.fixture
def bg_server(qapp, _isolate_settings):
    """Background-mode server + controller."""
    ctrl = SlideshowController()
    port = _free_port()
    srv = RemoteServer(ctrl, port=port, background_mode=True)
    srv.start()
    yield ctrl, srv, port
    srv.stop()


class TestRescanEndpoint:
    def test_rescan_returns_404_in_normal_mode(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        assert _http_status(qtbot, f"http://127.0.0.1:{port}/control/rescan") == 404

    def test_rescan_returns_409_while_show_running(self, bg_server, qtbot):
        _, srv, port = bg_server
        srv.setShowStarted(True)
        assert _http_status(qtbot, f"http://127.0.0.1:{port}/control/rescan") == 409

    def test_rescan_emits_signal_in_standby(self, bg_server, qtbot):
        _, srv, port = bg_server
        srv.setShowStarted(False)
        received = []
        srv.rescanRequested.connect(lambda: received.append(True))
        _http_status(qtbot, f"http://127.0.0.1:{port}/control/rescan")
        qtbot.waitUntil(lambda: len(received) > 0, timeout=3000)
        assert received


class TestRescanIntervalEndpoint:
    def test_rescan_interval_returns_404_in_normal_mode(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/rescan-interval?value=300"
        ) == 404

    def test_rescan_interval_rejects_invalid_value(self, bg_server, qtbot):
        _, _, port = bg_server
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/rescan-interval?value=999"
        ) == 400

    def test_rescan_interval_rejects_missing_value(self, bg_server, qtbot):
        _, _, port = bg_server
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/rescan-interval"
        ) == 400

    def test_rescan_interval_emits_signal_for_valid_value(self, bg_server, qtbot):
        _, srv, port = bg_server
        received = []
        srv.rescanIntervalChangeRequested.connect(lambda secs: received.append(secs))
        _http_status(qtbot, f"http://127.0.0.1:{port}/control/rescan-interval?value=600")
        qtbot.waitUntil(lambda: len(received) > 0, timeout=3000)
        assert received[0] == 600

    def test_rescan_interval_zero_is_valid(self, bg_server, qtbot):
        _, srv, port = bg_server
        received = []
        srv.rescanIntervalChangeRequested.connect(lambda secs: received.append(secs))
        _http_status(qtbot, f"http://127.0.0.1:{port}/control/rescan-interval?value=0")
        qtbot.waitUntil(lambda: len(received) > 0, timeout=3000)
        assert received[0] == 0


# ── /control/transition ────────────────────────────────────────────────────────

class TestTransitionEndpoint:
    def test_transition_returns_404_in_normal_mode(self, server_and_ctrl, qtbot):
        _, _, port = server_and_ctrl
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/transition?value=fade"
        ) == 404

    def test_transition_rejects_invalid_value(self, bg_server, qtbot):
        _, _, port = bg_server
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/transition?value=dissolve"
        ) == 400

    def test_transition_rejects_missing_value(self, bg_server, qtbot):
        _, _, port = bg_server
        assert _http_status(
            qtbot, f"http://127.0.0.1:{port}/control/transition"
        ) == 400

    @pytest.mark.parametrize("style", ["fade", "slide", "zoom", "fadeblack"])
    def test_transition_emits_signal_for_valid_style(self, bg_server, qtbot, style):
        _, srv, port = bg_server
        received = []
        srv.transitionChangeRequested.connect(lambda s: received.append(s))
        _http_status(qtbot, f"http://127.0.0.1:{port}/control/transition?value={style}")
        qtbot.waitUntil(lambda: len(received) > 0, timeout=3000)
        assert received[0] == style

    def test_status_includes_transition(self, bg_server, qtbot):
        ctrl, _, port = bg_server
        _, body = _http_get(qtbot, f"http://127.0.0.1:{port}/status")
        data = json.loads(body)
        assert "transition" in data
        assert data["transition"] == ctrl.transitionStyle


# ── setPort ────────────────────────────────────────────────────────────────────

class TestSetPort:
    def test_set_port_same_value_is_noop(self, qapp, _isolate_settings):
        ctrl = SlideshowController()
        port = _free_port()
        srv = RemoteServer(ctrl, port=port)
        srv.start()
        # Setting same port should not restart
        srv.setPort(port)
        assert srv._server.isListening()
        srv.stop()

    def test_set_port_restarts_on_new_port(self, qapp, _isolate_settings, qtbot):
        ctrl = SlideshowController()
        port1 = _free_port()
        srv = RemoteServer(ctrl, port=port1)
        srv.start()
        assert srv._server.isListening()

        port2 = _free_port()
        srv.setPort(port2)
        qtbot.wait(50)
        assert srv._server.isListening()
        assert srv._port == port2
        srv.stop()
