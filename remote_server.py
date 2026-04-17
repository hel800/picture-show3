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

  /* ── Exact Theme.qml colours ───────────────────────────────── */
  :root {
    --bg-deep:       #111820;
    --bg-card:       #131e2a;
    --surface:       #1e293a;
    --surface-hover: #293952;
    --accent-deep:   #20293d;
    --accent-press:  #32405e;
    --accent:        #526796;
    --accent-light:  #96a5c5;
    --text-primary:  #e2e8f0;
    --text-sec:      #94a3b8;
    --text-muted:    #475569;
    --text-disabled: #6d84a5;
    --warn:          #7c5c1e;
    --warn-text:     #fcd34d;
  }

  body {
    background: var(--bg-deep);
    color: var(--text-primary);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-start;
    gap: 20px;
    padding: 24px;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }

  /* ── Header ──────────────────────────────────────── */
  header { text-align: center; }
  header img { width: 200px; max-width: 75vw; }
  #status {
    font-size: .85rem;
    color: var(--text-disabled);
    margin-top: 8px;
    min-height: 1.4em;
  }

  /* ── Segmented control — matches AdvancedSettingsDialog exactly ─── */
  /* QML: outer Rectangle height:36 radius:10 color:Theme.surface        */
  /* QML: active tab color=bgCard border.color=accent border.width=1     */
  .seg-bar {
    display: flex;
    gap: 3px;
    background: var(--surface);
    border-radius: 10px;
    padding: 3px;
    width: 100%;
    max-width: 420px;
  }
  .seg-tab {
    flex: 1;
    padding: 8px;
    border-radius: 8px;
    background: transparent;
    border: 1px solid transparent;
    color: var(--text-muted);
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: background .12s, border-color .12s, color .12s;
  }
  .seg-tab.active {
    background: var(--bg-card);
    border-color: var(--accent);
    color: var(--accent-light);
  }
  .seg-tab:active:not(:disabled) { transform: scale(.97); }

  /* ── Section containers ───────────────────────────────── */
  #remoteSection, #pfSection { width: 100%; max-width: 420px; }

  /* ── Remote nav buttons ──────────────────────────────── */
  .remote-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .nav-btn {
    padding: 28px 8px;
    border: 1px solid var(--surface);
    border-radius: 14px;
    background: var(--bg-card);
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    transition: transform .1s, background .12s, border-color .12s, opacity .2s;
  }
  .nav-btn svg { width: 2em; height: 2em; pointer-events: none; }
  .nav-btn:active:not(:disabled) {
    transform: scale(.92);
    background: var(--accent-press);
    border-color: var(--accent);
  }
  .nav-btn:disabled { opacity: .25; cursor: not-allowed; }
  .play-btn {
    grid-column: 1 / -1;
    padding: 20px;
    border: 1px solid var(--surface);
    border-radius: 14px;
    background: var(--bg-card);
    cursor: pointer;
    display: flex; align-items: center; justify-content: center; gap: 10px;
    transition: transform .1s, background .12s, border-color .12s, opacity .2s;
  }
  .play-btn img { height: 1.5em; pointer-events: none; }
  .play-btn .play-lbl { color: var(--text-sec); font-size: .95rem; }
  .play-btn:active:not(:disabled) {
    transform: scale(.97);
    background: var(--accent-press);
    border-color: var(--accent);
  }
  .play-btn:disabled { opacity: .25; cursor: not-allowed; }

  /* ── Picture Frame section ──────────────────────────── */
  .opt-item { padding: 14px 0; }
  /* Thin divider — QML: height:1, color:Theme.surface */
  .divider { height: 1px; background: var(--surface); }

  /* Section label: 3 px accent bar + small-caps text (exact QML match) */
  .opt-lbl {
    display: flex; align-items: center; gap: 8px;
    margin-bottom: 14px;
  }
  .opt-bar {
    width: 3px; height: 11px; border-radius: 1.5px;
    background: var(--accent); flex-shrink: 0;
  }
  .opt-lbl span {
    font-size: 11px; font-weight: 600;
    letter-spacing: 1.4px; text-transform: uppercase;
    color: var(--accent-light);
  }

  /* Content row */
  .opt-row {
    display: flex; align-items: center;
    justify-content: space-between; gap: 12px;
  }
  .opt-title { font-size: 14px; color: var(--text-primary); }
  .opt-value {
    font-size: 13px; font-weight: 500;
    color: var(--accent-light);
    font-variant-numeric: tabular-nums;
  }

  /* Action buttons — styled like the dialog Done button */
  .action-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .action-btn {
    display: flex; align-items: center; justify-content: center; gap: 8px;
    padding: 15px 8px;
    border-radius: 10px;
    background: var(--surface);
    border: 1px solid transparent;
    color: var(--text-primary);
    font-size: 14px;
    cursor: pointer;
    transition: transform .1s, background .12s, border-color .12s, opacity .2s;
  }
  .action-btn:active:not(:disabled) {
    transform: scale(.96);
    background: var(--accent-press);
    border-color: var(--accent);
  }
  .action-btn:disabled { opacity: .25; cursor: not-allowed; }
  .action-btn svg { width: 1em; height: 1em; flex-shrink: 0; pointer-events: none; }

  /* Scale chips — matches QML image-scale selector (icon 20px + label) */
  .chip-group { display: flex; gap: 8px; }
  .chip {
    flex: 1;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 5px;
    padding: 14px 8px;
    min-width: 72px;
    border-radius: 12px;
    background: var(--surface);
    border: 1px solid transparent;
    color: var(--text-muted);
    font-size: 11px;
    cursor: pointer;
    transition: background .15s, border-color .15s, color .15s;
  }
  .chip:active { transform: scale(.95); }
  .chip.active {
    background: var(--accent-press);
    border-color: var(--accent);
    color: var(--accent-light);
  }
  .chip:disabled { opacity: .25; cursor: not-allowed; }
  .chip img { width: 20px; height: 20px; opacity: .45; pointer-events: none; }
  .chip.active img { opacity: 1; }

  /* Slider — QML: 4 px track, accent fill, 22×22 handle w/ accent border */
  .slider-block { display: flex; flex-direction: column; gap: 8px; }
  .slider-hdr { display: flex; justify-content: space-between; align-items: baseline; }
  .slider-ends { display: flex; justify-content: space-between; }
  .slider-ends span { font-size: 11px; color: var(--text-disabled); }
  input[type=range] {
    -webkit-appearance: none; appearance: none;
    width: 100%; height: 4px; border-radius: 2px;
    background: var(--surface);
    outline: none; cursor: pointer;
    margin: 12px 0 4px;  /* vertical room for the 22px thumb */
  }
  input[type=range]::-webkit-slider-thumb {
    -webkit-appearance: none; appearance: none;
    width: 22px; height: 22px; border-radius: 11px;
    background: var(--accent-light);
    border: 2px solid var(--accent);
    cursor: pointer;
  }
  input[type=range]::-moz-range-thumb {
    width: 22px; height: 22px; border-radius: 11px;
    background: var(--accent-light);
    border: 2px solid var(--accent);
    cursor: pointer;
  }

  /* Warning banner */
  #pfWarning {
    background: var(--warn); color: var(--warn-text);
    border-radius: 8px; padding: 10px 14px;
    font-size: .85rem; margin-bottom: 4px; display: none;
  }

  footer { font-size: .7rem; color: var(--surface); text-align: center; }
</style>
</head>
<body>

<header>
  <img src="/logo.svg" alt="Picture Show Remote">
  <div id="status">Waiting for show to start…</div>
</header>

<!-- Segmented section selector (background mode only) -->
<div class="seg-bar" id="tabBar" style="display:none">
  <button class="seg-tab active" id="tabRemote"   onclick="switchTab('remote')">Remote</button>
  <button class="seg-tab"        id="tabPicframe" onclick="switchTab('picframe')">Picture Frame</button>
</div>

<!-- Remote section -->
<div id="remoteSection">
  <div class="remote-grid">
    <button class="nav-btn" id="prevBtn" onclick="cmd('prev')" title="Previous" disabled>
      <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
        <path d="M 20,8 10,16 20,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
    </button>
    <button class="nav-btn" id="nextBtn" onclick="cmd('next')" title="Next" disabled>
      <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
        <path d="M 12,8 22,16 12,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
    </button>
    <button class="play-btn" id="playBtn" onclick="cmd('toggle')" disabled>
      <img id="playBtnIcon" src="/icon_play.svg">
      <span class="play-lbl" id="playBtnLabel">Play</span>
    </button>
  </div>
</div>

<!-- Picture Frame section (background mode only) -->
<div id="pfSection" style="display:none">

  <div id="pfWarning">No images found in the configured folder.</div>

  <!-- SHOW CONTROL -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span>Show Control</span></div>
    <div class="action-row">
      <button class="action-btn" id="pfStartBtn" onclick="pfStart()">
        <svg viewBox="0 0 16 16" fill="currentColor"><polygon points="3,1 14,8 3,15"/></svg>
        Start Show
      </button>
      <button class="action-btn" id="pfStopBtn" onclick="pfStop()" disabled>
        <svg viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="12" height="12" rx="2"/></svg>
        End Show
      </button>
    </div>
  </div>

  <div class="divider"></div>

  <!-- INTERVAL -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span>Interval</span></div>
    <div class="slider-block">
      <div class="slider-hdr">
        <span class="opt-title">Autoplay interval</span>
        <span class="opt-value" id="pfIntervalLabel">5m</span>
      </div>
      <input type="range" id="pfIntervalSlider" min="0" max="92"
             oninput="pfIntervalInput(this.value)"
             onchange="pfIntervalCommit(this.value)">
      <div class="slider-ends"><span>10s</span><span>24h</span></div>
    </div>
  </div>

  <div class="divider"></div>

  <!-- SCALE -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span>Scale</span></div>
    <div class="opt-row">
      <span class="opt-title">Image scale</span>
      <div class="chip-group">
        <button class="chip" id="pfFitChip" onclick="pfScale('fit')">
          <img src="/icon_scale_fit.svg" alt=""><span>Fit</span>
        </button>
        <button class="chip" id="pfFillChip" onclick="pfScale('fill')">
          <img src="/icon_scale_fill.svg" alt=""><span>Fill</span>
        </button>
      </div>
    </div>
  </div>

</div>

<footer>v__APP_VERSION__</footer>

<script>
  // ── Non-linear interval steps ─────────────────────────────────────────
  // 10s–59s: 1s  |  1m–10m: 1m  |  15m–55m: 5m  |  1h–24h: 1h
  var STEPS = (function() {
    var s = [];
    for (var i = 10; i < 60; i++)       s.push(i);
    for (var i = 1; i <= 10; i++)       s.push(i * 60);
    for (var i = 15; i <= 55; i += 5)   s.push(i * 60);
    for (var i = 1; i <= 24; i++)       s.push(i * 3600);
    return s;
  })();
  var SLIDER_MAX = STEPS.length - 1;
  document.getElementById('pfIntervalSlider').max = SLIDER_MAX;

  function sliderToMs(v) { return STEPS[parseInt(v)] * 1000; }
  function msToSlider(ms) {
    var s = Math.round(ms / 1000);
    if (s <= STEPS[0]) return 0;
    if (s >= STEPS[SLIDER_MAX]) return SLIDER_MAX;
    for (var i = 0; i < SLIDER_MAX; i++) {
      if (STEPS[i] === s) return i;
      if (STEPS[i] < s && STEPS[i + 1] > s)
        return (s - STEPS[i] <= STEPS[i + 1] - s) ? i : i + 1;
    }
    return SLIDER_MAX;
  }
  function fmtSeconds(s) {
    if (s < 60) return s + 's';
    if (s < 3600) return (s / 60) + 'm';
    return (s / 3600) + 'h';
  }

  // Accent-filled track (matches QML slider fill rectangle)
  function sliderFill(el) {
    var pct = ((parseInt(el.value) - parseInt(el.min)) /
               (parseInt(el.max)  - parseInt(el.min)) * 100).toFixed(1);
    el.style.background =
      'linear-gradient(to right,#526796 ' + pct + '%,#1e293a ' + pct + '%)';
  }

  // ── Debounce for slider ─────────────────────────────────────────
  var _itimer = null;
  function pfIntervalInput(v) {
    document.getElementById('pfIntervalLabel').textContent = fmtSeconds(STEPS[parseInt(v)]);
    sliderFill(document.getElementById('pfIntervalSlider'));
    clearTimeout(_itimer);
    _itimer = setTimeout(function() { pfIntervalCommit(v); }, 600);
  }
  function pfIntervalCommit(v) {
    clearTimeout(_itimer);
    document.getElementById('pfIntervalLabel').textContent = fmtSeconds(STEPS[parseInt(v)]);
    sliderFill(document.getElementById('pfIntervalSlider'));
    fetch('/control/interval?value=' + sliderToMs(v)).catch(function(){});
  }

  // ── Scale chips ─────────────────────────────────────────────
  function pfScale(mode) {
    fetch('/control/scale?value=' + mode).catch(function(){});
    updateScaleChips(mode);
  }
  function updateScaleChips(mode) {
    document.getElementById('pfFitChip').classList.toggle('active',  mode === 'fit');
    document.getElementById('pfFillChip').classList.toggle('active', mode === 'fill');
  }

  // ── Start / stop ────────────────────────────────────────────
  function pfStart() { fetch('/control/start').catch(function(){}); setTimeout(poll, 300); }
  function pfStop()  { fetch('/control/stop').catch(function(){});  setTimeout(poll, 300); }

  // ── Tab switching ───────────────────────────────────────────
  function switchTab(tab) {
    document.getElementById('remoteSection').style.display = tab === 'remote'   ? '' : 'none';
    document.getElementById('pfSection').style.display     = tab === 'picframe' ? '' : 'none';
    document.getElementById('tabRemote').classList.toggle('active',   tab === 'remote');
    document.getElementById('tabPicframe').classList.toggle('active', tab === 'picframe');
  }

  // ── Standard remote ─────────────────────────────────────────
  function cmd(action) {
    fetch('/' + action).catch(function(){});
    setTimeout(poll, 300);
  }

  // ── Polling ───────────────────────────────────────────────
  var _bgMode    = __BACKGROUND_MODE__;
  var _firstPoll = true;
  var _online    = true;

  if (_bgMode) document.getElementById('tabBar').style.display = '';

  function setOffline() {
    if (!_online) return;
    _online = false;
    ['prevBtn', 'nextBtn', 'playBtn'].forEach(function(id) {
      document.getElementById(id).disabled = true;
    });
    if (_bgMode) {
      ['pfStartBtn', 'pfStopBtn', 'pfIntervalSlider', 'pfFitChip', 'pfFillChip'].forEach(
        function(id) { document.getElementById(id).disabled = true; }
      );
    }
    document.getElementById('status').style.color = '#fcd34d';
    document.getElementById('status').textContent  = 'Picture Show is not running.';
  }

  function setOnline() {
    if (_online) return;
    _online = true;
    _firstPoll = true;
    document.getElementById('status').style.color = '';
  }

  function poll() {
    var ctrl = new AbortController();
    var tid  = setTimeout(function() { ctrl.abort(); }, 2500);
    fetch('/status', { signal: ctrl.signal })
      .then(function(r) { clearTimeout(tid); return r.json(); })
      .then(function(d) {
        setOnline();
        var active   = d.active;
        var playing  = d.playing;
        var total    = d.total;
        var scanning = d.scanning;

        // Remote section
        document.getElementById('prevBtn').disabled = !active;
        document.getElementById('nextBtn').disabled = !active;
        document.getElementById('playBtn').disabled = !active;
        document.getElementById('status').textContent = active
          ? 'Photo ' + (d.index + 1) + ' of ' + total +
            (playing ? '\u2002(Playing)' : '\u2002(Paused)')
          : 'Waiting for show to start\u2026';
        document.getElementById('playBtnIcon').src =
          playing ? '/icon_pause.svg' : '/icon_play.svg';
        document.getElementById('playBtnLabel').textContent =
          playing ? 'Pause' : 'Play';

        // Picture Frame section
        if (_bgMode) {
          var ss = d.show_started;
          document.getElementById('pfStartBtn').disabled =
            ss || (!scanning && total === 0);
          document.getElementById('pfStopBtn').disabled    = !ss;
          document.getElementById('pfIntervalSlider').disabled = false;
          document.getElementById('pfFitChip').disabled    = false;
          document.getElementById('pfFillChip').disabled   = false;

          document.getElementById('pfWarning').style.display =
            (!scanning && total === 0) ? '' : 'none';

          var slider = document.getElementById('pfIntervalSlider');
          if (_firstPoll || !slider.matches(':active')) {
            var idx = msToSlider(d.interval);
            slider.value = idx;
            document.getElementById('pfIntervalLabel').textContent =
              fmtSeconds(STEPS[idx]);
            sliderFill(slider);
          }
          updateScaleChips(d.scale);
        }
        _firstPoll = false;
      })
      .catch(function() { setOffline(); });
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
            case "/icon_scale_fit.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_scale_fit.svg"))
            case "/icon_scale_fill.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_scale_fill.svg"))

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
