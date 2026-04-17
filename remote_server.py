# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
RemoteServer — tiny HTTP server for smartphone remote control.
Serves a touch-friendly web page and responds to /next /prev /toggle /status.
No external dependencies — uses Qt's own QTcpServer.

Background mode adds a Picture Frame section (/control/* routes) for
starting/stopping the show and adjusting interval and scale on the fly.

Requires Python >= 3.14
"""
from __future__ import annotations

import json
import socket
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

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
    --bg:           #111820;
    --card:         #131e2a;
    --btn:          #1e293a;
    --btn-hover:    #293952;
    --accent:       #526796;
    --accent-press: #32405e;
    --accent-light: #96a5c5;
    --text:         #e2e8f0;
    --text-sec:     #94a3b8;
    --muted:        #64748b;
    --border:       #252c40;
    --warn:         #7c5c1e;
    --warn-text:    #fcd34d;
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
    border: 1px solid var(--border);
    border-radius: 12px;
    background: var(--btn);
    color: var(--text);
    cursor: pointer;
    transition: transform .1s, background .15s, border-color .15s, opacity .2s;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  button svg { width: 2em; height: 2em; pointer-events: none; }
  button:active:not(:disabled) {
    transform: scale(.92);
    background: var(--accent-press);
    border-color: var(--accent);
  }
  button:disabled { opacity: 0.25; cursor: not-allowed; }
  .wide {
    grid-column: 1 / -1;
    padding: 22px;
    gap: 10px;
  }
  .wide img { height: 1.6em; vertical-align: middle; pointer-events: none; }
  .wide .label { color: var(--text-sec); font-size: .95rem; }
  /* ── Picture Frame section ───────────────────────────────────────────── */
  #pfSection {
    width: 100%;
    max-width: 340px;
    border: 1px solid var(--border);
    border-radius: 14px;
    overflow: hidden;
  }
  .pf-header {
    background: var(--card);
    padding: 12px 16px;
    font-size: .8rem;
    font-weight: 600;
    letter-spacing: .08em;
    text-transform: uppercase;
    color: var(--text-sec);
    border-bottom: 1px solid var(--border);
  }
  .pf-body {
    background: var(--card);
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .pf-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  .pf-btn {
    padding: 18px 8px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--btn);
    color: var(--text);
    font-size: .9rem;
    cursor: pointer;
    transition: transform .1s, background .15s, border-color .15s, opacity .2s;
  }
  .pf-btn:active:not(:disabled) {
    transform: scale(.95);
    background: var(--accent-press);
    border-color: var(--accent);
  }
  .pf-btn:disabled { opacity: 0.25; cursor: not-allowed; }
  .pf-btn.active {
    border-color: var(--accent);
    color: var(--accent-light);
  }
  .pf-label {
    font-size: .8rem;
    color: var(--text-sec);
    margin-bottom: 4px;
  }
  .pf-slider-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .pf-slider-top {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .pf-slider-val {
    font-size: .95rem;
    color: var(--text);
    font-variant-numeric: tabular-nums;
  }
  input[type=range] {
    -webkit-appearance: none;
    appearance: none;
    width: 100%;
    height: 6px;
    border-radius: 3px;
    background: var(--border);
    outline: none;
    cursor: pointer;
  }
  input[type=range]::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--accent-light);
    cursor: pointer;
  }
  input[type=range]::-moz-range-thumb {
    width: 20px;
    height: 20px;
    border: none;
    border-radius: 50%;
    background: var(--accent-light);
    cursor: pointer;
  }
  .pf-scale-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .pf-scale-btns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  #pfWarning {
    background: var(--warn);
    color: var(--warn-text);
    border-radius: 8px;
    padding: 10px 12px;
    font-size: .85rem;
    text-align: center;
    display: none;
  }
  footer { font-size: .75rem; color: var(--border); text-align: center; }
</style>
</head>
<body>
<header>
  <img src="/logo.svg" alt="Picture Show Remote">
  <div id="status">Waiting for show to start\u2026</div>
</header>

<div class="grid">
  <button id="prevBtn" onclick="cmd('prev')" title="Previous" disabled>
    <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
      <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
      <path d="M 20,8 10,16 20,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    </svg>
  </button>
  <button id="nextBtn" onclick="cmd('next')" title="Next" disabled>
    <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
      <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
      <path d="M 12,8 22,16 12,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    </svg>
  </button>
  <button class="wide" id="playBtn" onclick="cmd('toggle')" disabled>
    <img id="playBtnIcon" src="/icon_play.svg"><span class="label" id="playBtnLabel"> Play</span>
  </button>
</div>

<div id="pfSection" style="display:none">
  <div class="pf-header">Picture Frame</div>
  <div class="pf-body">

    <div id="pfWarning">No images found in the configured folder.</div>

    <div class="pf-row">
      <button class="pf-btn" id="pfStartBtn" onclick="pfStart()">Start Show</button>
      <button class="pf-btn" id="pfStopBtn"  onclick="pfStop()"  disabled>End Show</button>
    </div>

    <div class="pf-slider-row">
      <div class="pf-slider-top">
        <span class="pf-label">Interval</span>
        <span class="pf-slider-val" id="pfIntervalLabel">5s</span>
      </div>
      <input type="range" id="pfIntervalSlider" min="0" max="1000"
             oninput="pfIntervalInput(this.value)"
             onchange="pfIntervalCommit(this.value)">
    </div>

    <div class="pf-scale-row">
      <span class="pf-label">Scale</span>
      <div class="pf-scale-btns">
        <button class="pf-btn" id="pfFitBtn"  onclick="pfScale('fit')">Fit</button>
        <button class="pf-btn" id="pfFillBtn" onclick="pfScale('fill')">Fill</button>
      </div>
    </div>

  </div>
</div>

<footer>v__APP_VERSION__</footer>

<script>
  // ── log-scale helpers (10 s … 86 400 s = 1 day) ──────────────────────────
  var MS_MIN  = 10000;
  var MS_MAX  = 86400000;
  var LOG_MIN = Math.log(MS_MIN);
  var LOG_MAX = Math.log(MS_MAX);

  function sliderToMs(v) {
    return Math.round(Math.exp(LOG_MIN + (LOG_MAX - LOG_MIN) * v / 1000));
  }
  function msToSlider(ms) {
    ms = Math.max(MS_MIN, Math.min(MS_MAX, ms));
    return Math.round((Math.log(ms) - LOG_MIN) / (LOG_MAX - LOG_MIN) * 1000);
  }
  function fmtMs(ms) {
    var s = Math.round(ms / 1000);
    if (s < 60)  return s + 's';
    var m = Math.floor(s / 60), rs = s % 60;
    if (m < 60)  return rs ? m + 'm ' + rs + 's' : m + 'm';
    var h = Math.floor(m / 60), rm = m % 60;
    if (h < 24)  return rm ? h + 'h ' + rm + 'm' : h + 'h';
    var d = Math.floor(h / 24), rh = h % 24;
    return rh ? d + 'd ' + rh + 'h' : d + 'd';
  }

  // ── debounce for slider input events ─────────────────────────────────────
  var _intervalTimer = null;
  function pfIntervalInput(v) {
    document.getElementById('pfIntervalLabel').textContent = fmtMs(sliderToMs(v));
    clearTimeout(_intervalTimer);
    _intervalTimer = setTimeout(function() { pfIntervalCommit(v); }, 600);
  }
  function pfIntervalCommit(v) {
    clearTimeout(_intervalTimer);
    var ms = sliderToMs(v);
    document.getElementById('pfIntervalLabel').textContent = fmtMs(ms);
    fetch('/control/interval?value=' + ms).catch(function(){});
  }

  // ── scale ─────────────────────────────────────────────────────────────────
  function pfScale(mode) {
    fetch('/control/scale?value=' + mode).catch(function(){});
    updateScaleBtns(mode);
  }
  function updateScaleBtns(mode) {
    document.getElementById('pfFitBtn').classList.toggle('active',  mode === 'fit');
    document.getElementById('pfFillBtn').classList.toggle('active', mode === 'fill');
  }

  // ── start / stop ──────────────────────────────────────────────────────────
  function pfStart() {
    fetch('/control/start').catch(function(){});
    setTimeout(poll, 300);
  }
  function pfStop() {
    fetch('/control/stop').catch(function(){});
    setTimeout(poll, 300);
  }

  // ── standard remote commands ──────────────────────────────────────────────
  function cmd(action) {
    fetch('/' + action).catch(function(){});
    setTimeout(poll, 300);
  }

  // ── polling ───────────────────────────────────────────────────────────────
  var _bgMode = __BACKGROUND_MODE__;
  var _firstPoll = true;
  var _online = true;

  function setOffline() {
    if (!_online) return;   // already offline — avoid redundant DOM writes
    _online = false;
    ['prevBtn', 'nextBtn', 'playBtn'].forEach(function(id) {
      document.getElementById(id).disabled = true;
    });
    if (_bgMode) {
      ['pfStartBtn', 'pfStopBtn', 'pfIntervalSlider', 'pfFitBtn', 'pfFillBtn'].forEach(function(id) {
        document.getElementById(id).disabled = true;
      });
    }
    document.getElementById('status').style.color = 'var(--warn-text)';
    document.getElementById('status').textContent = 'Picture Show is not running.';
  }

  function setOnline() {
    if (_online) return;
    _online = true;
    _firstPoll = true;   // re-initialise slider on reconnect
    document.getElementById('status').style.color = '';
  }

  function poll() {
    var ctrl = new AbortController();
    var tid  = setTimeout(function() { ctrl.abort(); }, 2500);
    fetch('/status', { signal: ctrl.signal })
      .then(function(r) { clearTimeout(tid); return r.json(); })
      .then(function(d) {
        setOnline();
        var active = d.active;
        var playing = d.playing;
        var total = d.total;
        var scanning = d.scanning;

        // standard remote buttons
        var btns = [
          document.getElementById('prevBtn'),
          document.getElementById('nextBtn'),
          document.getElementById('playBtn'),
        ];
        btns.forEach(function(b) { b.disabled = !active; });
        document.getElementById('status').textContent = active
          ? 'Photo ' + (d.index + 1) + ' of ' + total + (playing ? '  (Playing)' : '  (Paused)')
          : 'Waiting for show to start\u2026';
        document.getElementById('playBtnIcon').src = playing ? '/icon_pause.svg' : '/icon_play.svg';
        document.getElementById('playBtnLabel').textContent = playing ? ' Pause' : ' Play';

        // picture frame section
        if (_bgMode) {
          document.getElementById('pfSection').style.display = '';

          var showStarted = d.show_started;
          document.getElementById('pfStartBtn').disabled = showStarted || (!scanning && total === 0);
          document.getElementById('pfStopBtn').disabled  = !showStarted;
          document.getElementById('pfIntervalSlider').disabled = false;
          document.getElementById('pfFitBtn').disabled  = false;
          document.getElementById('pfFillBtn').disabled = false;

          // no-images warning
          var warn = document.getElementById('pfWarning');
          warn.style.display = (!scanning && total === 0) ? '' : 'none';

          // interval slider — initialise on first poll, then only update if not dragging
          var slider = document.getElementById('pfIntervalSlider');
          if (_firstPoll || !slider.matches(':active')) {
            slider.value = msToSlider(d.interval);
            document.getElementById('pfIntervalLabel').textContent = fmtMs(d.interval);
          }

          // scale buttons
          updateScaleBtns(d.scale);
        }

        _firstPoll = false;
      })
      .catch(function() {
        setOffline();
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

    # ── Background mode signals ────────────────────────────────────────────────
    startShowRequested      = Signal()     # /control/start received
    stopShowRequested       = Signal()     # /control/stop received
    intervalChangeRequested = Signal(int)  # /control/interval — ms value
    scaleChangeRequested    = Signal(str)  # /control/scale — "fit" | "fill"
    showStartedChanged      = Signal()     # show_started flag changed (QML binding)

    def __init__(
        self,
        controller: SlideshowController,
        port: int = 8765,
        version: str = "",
        background_mode: bool = False,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._controller      = controller
        self._port            = port
        self._version         = version
        self._background_mode = background_mode
        self._show_active     = False
        self._show_started    = False   # background mode: window has been shown
        self._server          = QTcpServer(self)
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

    @Property(bool, notify=showStartedChanged)
    def showStarted(self) -> bool:
        """Background mode: true while the show window is currently visible."""
        return self._show_started

    @Slot(bool)
    def setShowStarted(self, started: bool) -> None:
        if self._show_started == started:
            return
        self._show_started = started
        self.showStartedChanged.emit()

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
        if sock in self._clients:
            self._clients.remove(sock)

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

    def _json_ok(self, sock: QTcpSocket) -> None:
        self._respond(sock, "200 OK", "application/json", '{"ok":true}')

    def _json_error(self, sock: QTcpSocket, msg: str, status: str = "400 Bad Request") -> None:
        body = json.dumps({"error": msg})
        self._respond(sock, status, "application/json", body)

    def _handle(self, sock: QTcpSocket) -> None:
        raw   = bytes(sock.readAll()).decode("utf-8", errors="ignore")
        parts = raw.split("\r\n", maxsplit=1)[0].split(" ") if raw else []
        if len(parts) < 2:
            self._respond(sock, "400 Bad Request", "text/plain", "bad request")
            return

        parsed      = urlparse(parts[1])
        path: _Path = parsed.path
        qs          = parse_qs(parsed.query)

        ctrl = self._controller
        match path:
            # ── static assets ─────────────────────────────────────────────
            case "/":
                bg_js = "true" if self._background_mode else "false"
                html  = (
                    _REMOTE_HTML
                    .replace("__APP_VERSION__", self._version)
                    .replace("__BACKGROUND_MODE__", bg_js)
                )
                self._respond(sock, "200 OK", "text/html; charset=utf-8", html)
            case "/logo.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("logo.svg"))
            case "/icon_play.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_play.svg"))
            case "/icon_pause.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_pause.svg"))

            # ── standard remote control ───────────────────────────────────
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
                    "index":        ctrl.currentIndex,
                    "total":        ctrl.imageCount,
                    "playing":      ctrl.isPlaying,
                    "active":       self._show_active,
                    "scanning":     ctrl.scanning,
                    # background mode fields (always present for simplicity)
                    "background_mode": self._background_mode,
                    "show_started": self._show_started,
                    "interval":     ctrl.interval,
                    "scale":        "fill" if ctrl.imageFill else "fit",
                })
                self._respond(sock, "200 OK", "application/json", body)

            # ── background mode: /control/ API ────────────────────────────
            case "/control/start":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                elif self._show_started:
                    self._json_error(sock, "show already started", "409 Conflict")
                else:
                    self.startShowRequested.emit()
                    self._json_ok(sock)

            case "/control/stop":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                elif not self._show_started:
                    self._json_error(sock, "show not started", "409 Conflict")
                else:
                    self.stopShowRequested.emit()
                    self._json_ok(sock)

            case "/control/interval":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                else:
                    try:
                        ms = int(qs.get("value", [""])[0])
                    except (ValueError, IndexError):
                        self._json_error(sock, "missing or invalid 'value' parameter")
                        return
                    # 10 s – 1 day in ms
                    if not (10_000 <= ms <= 86_400_000):
                        self._json_error(sock, "value out of range (10000–86400000 ms)")
                        return
                    self.intervalChangeRequested.emit(ms)
                    self._json_ok(sock)

            case "/control/scale":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                else:
                    value = qs.get("value", [""])[0]
                    if value not in ("fit", "fill"):
                        self._json_error(sock, "value must be 'fit' or 'fill'")
                        return
                    self.scaleChangeRequested.emit(value)
                    self._json_ok(sock)

            # ── reserved for future schedule API ─────────────────────────
            # /control/schedule/* routes will be added here
            case p if p.startswith("/control/schedule"):
                self._json_error(sock, "schedule API not yet implemented", "501 Not Implemented")

            case _:
                self._respond(sock, "404 Not Found", "text/plain", "not found")
