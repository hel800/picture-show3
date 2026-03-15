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
RemoteServer — tiny HTTP server for smartphone remote control.
Serves a touch-friendly web page and responds to /next /prev /toggle /status.
No external dependencies — uses Qt's own QTcpServer.

Requires Python >= 3.14
"""
from __future__ import annotations

import json
import socket
import sys
from pathlib import Path

# Dev: read img files directly from the filesystem.
# Frozen: read from the compiled Qt resource bundle (qrc:/).
_FROZEN  = getattr(sys, "frozen", False)
_IMG_DIR = Path(__file__).parent / "img"   # used in dev mode only


def _read_img(filename: str) -> bytes:
    """Read an img/ file from qrc (frozen) or filesystem (dev)."""
    if _FROZEN:
        f = QFile(f":/img/{filename}")
        f.open(QIODeviceBase.OpenModeFlag.ReadOnly)
        data = bytes(f.readAll())
        f.close()
        return data
    return (_IMG_DIR / filename).read_bytes()

from PySide6.QtCore import Property, QFile, QIODeviceBase, QObject, Signal, Slot
from PySide6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket

from slideshow_controller import SlideshowController

# ── Remote control web page ────────────────────────────────────────────────────
_REMOTE_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<title>Picture Show Remote</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  :root {
    --bg:     #0f0f1a;
    --card:   #1a1a2e;
    --btn:    #1e1e3a;
    --accent: #7c3aed;
    --text:   #e2e8f0;
    --muted:  #64748b;
  }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 32px;
    padding: 24px;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }
  header { text-align: center; }
  header img { width: 220px; max-width: 80vw; }
  #status { font-size: .9rem; color: var(--muted); margin-top: 10px; min-height: 1.4em; }
  .grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    width: 100%;
    max-width: 340px;
  }
  button {
    padding: 32px 8px;
    border: none;
    border-radius: 20px;
    font-size: 2rem;
    background: var(--btn);
    color: var(--text);
    cursor: pointer;
    transition: transform .1s, background .15s, opacity .2s;
  }
  button:active:not(:disabled) { transform: scale(.92); background: var(--accent); }
  button:disabled { opacity: 0.25; cursor: not-allowed; }
  button img { height: 1.4em; vertical-align: middle; pointer-events: none; }
  .wide { grid-column: 1 / -1; font-size: 1.1rem; padding: 22px; }
  kbd {
    display: inline-block;
    background: var(--card);
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: .75rem;
    color: var(--muted);
  }
  footer { font-size: .75rem; color: #334155; text-align: center; }
</style>
</head>
<body>
<header>
  <img src="/logo.svg" alt="Picture Show Remote">
  <div id="status">Waiting for show to start…</div>
</header>

<div class="grid">
  <button id="prevBtn" onclick="cmd('prev')" title="Previous" disabled>◀</button>
  <button id="nextBtn" onclick="cmd('next')" title="Next" disabled>▶</button>
  <button class="wide" id="playBtn" onclick="cmd('toggle')" disabled>
    <img id="playBtnIcon" src="/icon_play.svg"><span id="playBtnLabel"> Play</span>
  </button>
</div>

<footer>
  On the picture show: <kbd>←</kbd><kbd>→</kbd> navigate &nbsp;·&nbsp;
  <kbd>Space</kbd> play/pause &nbsp;·&nbsp; <kbd>Esc</kbd> exit
</footer>

<script>
  function cmd(action) {
    fetch('/' + action).catch(() => {});
    setTimeout(poll, 300);
  }

  function poll() {
    fetch('/status')
      .then(r => r.json())
      .then(({ index, total, playing, active }) => {
        const btns = [
          document.getElementById('prevBtn'),
          document.getElementById('nextBtn'),
          document.getElementById('playBtn'),
        ];
        btns.forEach(b => b.disabled = !active);
        document.getElementById('status').textContent = active
          ? 'Photo ' + (index + 1) + ' of ' + total + (playing ? '  (Playing)' : '  (Paused)')
          : 'Waiting for show to start\u2026';
        document.getElementById('playBtnIcon').src = playing ? '/icon_pause.svg' : '/icon_play.svg';
        document.getElementById('playBtnLabel').textContent = playing ? ' Pause' : ' Play';
      })
      .catch(() => {
        document.getElementById('status').textContent = 'Reconnecting…';
      });
  }

  poll();
  setInterval(poll, 3000);
</script>
</body>
</html>
"""

type _Path = str   # HTTP path string


class RemoteServer(QObject):
    serverStarted = Signal(str)     # emits the URL when listening begins

    def __init__(
        self,
        controller: SlideshowController,
        port: int = 8765,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._controller  = controller
        self._port        = port
        self._show_active = False
        self._server      = QTcpServer(self)
        self._clients: list[QTcpSocket] = []
        self._server.newConnection.connect(self._on_new_connection)

    # ── Public API ─────────────────────────────────────────────────────────────
    @Property(str, notify=serverStarted)
    def url(self) -> str:
        return f"http://{self._local_ip()}:{self._port}"

    @Slot()
    def start(self) -> None:
        if not self._server.isListening():
            if self._server.listen(QHostAddress.Any, self._port):
                self.serverStarted.emit(self.url)

    @Slot(int)
    def setPort(self, port: int) -> None:
        if port == self._port:
            return
        was_listening = self._server.isListening()
        if was_listening:
            self.stop()
        self._port = port
        if was_listening:
            self.start()

    @Slot()
    def stop(self) -> None:
        for client in list(self._clients):
            client.disconnectFromHost()
        self._server.close()

    @Slot(bool)
    def setShowActive(self, active: bool) -> None:
        self._show_active = active

    # ── Internals ──────────────────────────────────────────────────────────────
    @staticmethod
    def _local_ip() -> str:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"

    def _on_new_connection(self) -> None:
        while self._server.hasPendingConnections():
            sock = self._server.nextPendingConnection()
            sock.readyRead.connect(lambda s=sock: self._handle(s))
            sock.disconnected.connect(lambda s=sock: self._drop(s))
            self._clients.append(sock)

    def _drop(self, sock: QTcpSocket) -> None:
        self._clients.remove(sock) if sock in self._clients else None

    def _respond(
        self,
        sock: QTcpSocket,
        status: str,
        ctype: str,
        body: str | bytes,
    ) -> None:
        if isinstance(body, str):
            body = body.encode()
        header = (
            f"HTTP/1.1 {status}\r\n"
            f"Content-Type: {ctype}\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Access-Control-Allow-Origin: *\r\n"
            f"Connection: close\r\n\r\n"
        )
        sock.write(header.encode() + body)
        sock.flush()
        sock.disconnectFromHost()

    def _handle(self, sock: QTcpSocket) -> None:
        raw   = bytes(sock.readAll()).decode("utf-8", errors="ignore")
        parts = raw.split("\r\n")[0].split(" ") if raw else []
        path: _Path = parts[1].split("?")[0] if len(parts) > 1 else "/"

        ctrl = self._controller
        match path:
            case "/":
                self._respond(sock, "200 OK", "text/html; charset=utf-8", _REMOTE_HTML)
            case "/logo.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("logo.svg"))
            case "/icon_play.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_play.svg"))
            case "/icon_pause.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_pause.svg"))
            case "/next":
                ctrl.nextImage()
                self._respond(sock, "200 OK", "text/plain", "ok")
            case "/prev":
                ctrl.prevImage()
                self._respond(sock, "200 OK", "text/plain", "ok")
            case "/toggle":
                ctrl.togglePlay()
                self._respond(sock, "200 OK", "text/plain", "ok")
            case "/status":
                body = json.dumps({
                    "index":   ctrl.currentIndex,
                    "total":   ctrl.imageCount,
                    "playing": ctrl.isPlaying,
                    "active":  self._show_active,
                })
                self._respond(sock, "200 OK", "application/json", body)
            case _:
                self._respond(sock, "404 Not Found", "text/plain", "not found")
