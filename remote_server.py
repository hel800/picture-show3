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

import io
import json
import socket
import sys
import threading
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

# ── Remote control translations ────────────────────────────────────────────────
_TRANSLATIONS: dict[str, dict[str, str]] = {
    "en": {
        "title":            "Picture Show Remote",
        "status_waiting":   "Waiting for show to start\u2026",
        "status_offline":   "Picture Show is not running.",
        "status_photo":     "Photo {n} of {total}",
        "status_playing":   "Playing",
        "status_paused":    "Paused",
        "tab_remote":       "Remote",
        "tab_picframe":     "Picture Frame",
        "btn_prev":         "Previous",
        "btn_next":         "Next",
        "play_play":        "Play",
        "play_pause":       "Pause",
        "btn_hud_show":     "Show Info Bar",
        "btn_hud_hide":     "Hide Info Bar",
        "btn_exif_show":    "Show Details",
        "btn_exif_hide":    "Hide Details",
        "preview_none":     "No preview available",
        "caption_prefix":   "Caption:",
        "caption_empty":    "<no caption>",
        "pf_warn_title":    "No images available",
        "pf_warn_sub":      "Check the folder path or filter settings.",
        "lbl_show_control": "Show Control",
        "btn_start_show":   "Start Show",
        "btn_end_show":     "End Show",
        "lbl_interval":     "Interval",
        "opt_interval":     "Autoplay interval",
        "lbl_scale":        "Scale",
        "opt_scale":        "Image scale",
        "chip_fit":         "Fit",
        "chip_fill":        "Fill",
        "lbl_transition":   "Transition",
        "chip_fade":        "Fade",
        "chip_slide":       "Slide",
        "chip_zoom":        "Zoom",
        "chip_fadeblack":   "Fade/Black",
        "btn_rescan":       "Scan Now",
        "btn_rescan_lbl":   "Rescan:",
        "lbl_rescan_bg":    "Rescan in Background",
        "chip_off":         "Off",
    },
    "de": {
        "title":            "Picture Show Fernbedienung",
        "status_waiting":   "Warte auf Showstart\u2026",
        "status_offline":   "Picture Show l\u00e4uft nicht.",
        "status_photo":     "Foto {n} von {total}",
        "status_playing":   "Wiedergabe",
        "status_paused":    "Pausiert",
        "tab_remote":       "Fernbedienung",
        "tab_picframe":     "Bilderrahmen",
        "btn_prev":         "Zur\u00fcck",
        "btn_next":         "Weiter",
        "play_play":        "Play",
        "play_pause":       "Pause",
        "btn_hud_show":     "Info-Leiste zeigen",
        "btn_hud_hide":     "Info-Leiste verbergen",
        "btn_exif_show":    "Details zeigen",
        "btn_exif_hide":    "Details verbergen",
        "preview_none":     "Keine Vorschau verf\u00fcgbar",
        "caption_prefix":   "Beschriftung:",
        "caption_empty":    "<keine Beschriftung>",
        "pf_warn_title":    "Keine Bilder verf\u00fcgbar",
        "pf_warn_sub":      "Ordnerpfad oder Filtereinstellungen pr\u00fcfen.",
        "lbl_show_control": "Show-Steuerung",
        "btn_start_show":   "Show starten",
        "btn_end_show":     "Show beenden",
        "lbl_interval":     "Intervall",
        "opt_interval":     "Autoplay-Intervall",
        "lbl_scale":        "Skalierung",
        "opt_scale":        "Bildskalierung",
        "chip_fit":         "Einpassen",
        "chip_fill":        "F\u00fcllen",
        "lbl_transition":   "\u00dcbergang",
        "chip_fade":        "Einblenden",
        "chip_slide":       "Schieben",
        "chip_zoom":        "Zoomen",
        "chip_fadeblack":   "Schwarz",
        "btn_rescan":       "Jetzt scannen",
        "btn_rescan_lbl":   "Rescan:",
        "lbl_rescan_bg":    "Hintergrundscan",
        "chip_off":         "Aus",
    },
    "fr": {
        "title":            "T\u00e9l\u00e9commande Picture Show",
        "status_waiting":   "En attente du d\u00e9marrage\u2026",
        "status_offline":   "Picture Show n\u2019est pas lanc\u00e9.",
        "status_photo":     "Photo {n} sur {total}",
        "status_playing":   "En lecture",
        "status_paused":    "En pause",
        "tab_remote":       "T\u00e9l\u00e9commande",
        "tab_picframe":     "Cadre photo",
        "btn_prev":         "Pr\u00e9c\u00e9dent",
        "btn_next":         "Suivant",
        "play_play":        "Lecture",
        "play_pause":       "Pause",
        "btn_hud_show":     "Afficher la barre d’infos",
        "btn_hud_hide":     "Masquer la barre d’infos",
        "btn_exif_show":    "Afficher les détails",
        "btn_exif_hide":    "Masquer les détails",
        "preview_none":     "Aucun aperçu disponible",
        "caption_prefix":   "Légende :",
        "caption_empty":    "<aucune légende>",
        "pf_warn_title":    "Aucune image disponible",
        "pf_warn_sub":      "V\u00e9rifiez le dossier ou les param\u00e8tres de filtre.",
        "lbl_show_control": "Contr\u00f4le du diaporama",
        "btn_start_show":   "D\u00e9marrer",
        "btn_end_show":     "Arr\u00eater",
        "lbl_interval":     "Intervalle",
        "opt_interval":     "Intervalle de lecture auto",
        "lbl_scale":        "Mise \u00e0 l\u2019\u00e9chelle",
        "opt_scale":        "\u00c9chelle de l\u2019image",
        "chip_fit":         "Adapter",
        "chip_fill":        "Remplir",
        "lbl_transition":   "Transition",
        "chip_fade":        "Fondu",
        "chip_slide":       "Glissement",
        "chip_zoom":        "Zoom",
        "chip_fadeblack":   "Fondu noir",
        "btn_rescan":       "Scanner maintenant",
        "btn_rescan_lbl":   "Rescan\u00a0:",
        "lbl_rescan_bg":    "Rescan en arri\u00e8re-plan",
        "chip_off":         "D\u00e9sactiv\u00e9",
    },
}

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
    --star-inactive: #30303b;
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
  /* Two-up row of play-style buttons (HUD + Details) */
  .btn-row {
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }
  .btn-row .play-btn { grid-column: auto; }
  /* Interval slider on the Remote tab */
  #intervalWrap { grid-column: 1 / -1; padding: 4px 4px 0; }
  #intervalWrap.disabled .interval-row { opacity: .45; }
  .interval-row {
    display: flex; justify-content: space-between; align-items: baseline;
    font-size: 12px;
  }
  .interval-row span:first-child { color: var(--text-sec); }
  #intervalLabel {
    color: var(--accent-light);
    font-variant-numeric: tabular-nums;
  }
  /* Divider used inside the Remote grid (spans both columns) */
  .remote-grid .divider { grid-column: 1 / -1; }

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

  /* Rescan interval select */
  select {
    width: 100%;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--surface);
    border: 1px solid transparent;
    color: var(--text-primary);
    font-size: 14px;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%2394a3b8' stroke-width='1.5' fill='none' stroke-linecap='round'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 12px center;
    padding-right: 32px;
    outline: none;
  }
  select:disabled { opacity: .25; cursor: not-allowed; }
  select option { background: var(--bg-card); }

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
  input[type=range]:disabled {
    opacity: .35;
    cursor: not-allowed;
  }
  input[type=range]:disabled::-webkit-slider-thumb {
    background: var(--text-muted);
    border-color: var(--text-disabled);
    cursor: not-allowed;
  }
  input[type=range]:disabled::-moz-range-thumb {
    background: var(--text-muted);
    border-color: var(--text-disabled);
    cursor: not-allowed;
  }

  /* Warning banner */
  #pfWarning {
    display: none;
    align-items: flex-start;
    gap: 12px;
    background: rgba(124, 92, 30, 0.25);
    border: 1px solid rgba(252, 211, 77, 0.3);
    border-radius: 10px;
    padding: 14px 16px;
    margin-bottom: 8px;
  }
  .warn-icon { color: var(--warn-text); flex-shrink: 0; margin-top: 1px; }
  .warn-title { font-size: .88rem; font-weight: 600; color: var(--warn-text); margin-bottom: 3px; }
  .warn-sub { font-size: .78rem; color: rgba(252, 211, 77, 0.6); line-height: 1.4; }

  /* Image preview */
  #previewWrap { grid-column: 1 / -1; }
  #previewBox {
    position: relative;
    aspect-ratio: 16 / 9;
    width: 100%;
    background: var(--surface);
    border-radius: 10px;
    overflow: hidden;
  }
  #previewBox img {
    position: absolute; inset: 0;
    width: 100%; height: 100%;
    object-fit: contain;
    opacity: 0;
    transition: opacity .7s ease;
  }
  #previewBox img.loaded { opacity: 1; }
  #previewPlaceholder {
    position: absolute; inset: 0;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 8px;
    color: var(--text-muted);
    font-size: .85rem;
  }
  #previewPlaceholder svg { width: 48px; height: 48px; opacity: .6; }
  #previewBox.active #previewPlaceholder { display: none; }
  #previewCounter, #previewRating {
    position: absolute;
    bottom: 8px;
    padding: 3px 10px;
    border-radius: 6px;
    background: rgba(0, 0, 0, 0.55);
    color: var(--text-primary);
    font-size: .8rem;
    pointer-events: none;
    display: none;
  }
  #previewCounter { left: 8px; font-variant-numeric: tabular-nums; }
  #previewRating  { right: 8px; letter-spacing: 1px; }
  #previewRating .star-on  { color: var(--accent-light); }
  #previewRating .star-off { color: var(--star-inactive); }
  #previewBox.active #previewCounter,
  #previewBox.active #previewRating { display: block; }
  #previewCaption {
    margin-top: 8px;
    font-size: .82rem;
    color: var(--text-sec);
    text-align: center;
    line-height: 1.4;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  footer { font-size: .7rem; color: var(--surface); text-align: center; }
</style>
</head>
<body>

<header>
  <img src="/logo.svg" alt="Picture Show Remote">
  <div id="status" data-i18n="status_waiting">Waiting for show to start…</div>
</header>

<!-- Segmented section selector (background mode only) -->
<div class="seg-bar" id="tabBar" style="display:none">
  <button class="seg-tab active" id="tabRemote"   onclick="switchTab('remote')"   data-i18n="tab_remote">Remote</button>
  <button class="seg-tab"        id="tabPicframe" onclick="switchTab('picframe')" data-i18n="tab_picframe">Picture Frame</button>
</div>

<!-- Remote section -->
<div id="remoteSection">
  <div class="remote-grid">
    <button class="nav-btn" id="prevBtn" onclick="cmd('prev')" data-i18n-title="btn_prev" title="Previous" disabled>
      <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
        <path d="M 20,8 10,16 20,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
    </button>
    <button class="nav-btn" id="nextBtn" onclick="cmd('next')" data-i18n-title="btn_next" title="Next" disabled>
      <svg viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <rect x="1" y="1" width="30" height="30" rx="6" fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>
        <path d="M 12,8 22,16 12,24" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
    </button>
    <button class="play-btn" id="playBtn" onclick="cmd('toggle')" disabled>
      <img id="playBtnIcon" src="/icon_play.svg">
      <span class="play-lbl" id="playBtnLabel" data-i18n="play_play">Play</span>
    </button>
    <div id="intervalWrap">
      <div class="interval-row">
        <span data-i18n="lbl_interval">Interval</span>
        <span id="intervalLabel">5s</span>
      </div>
      <input type="range" id="intervalSlider" min="1" max="99" value="5"
             oninput="intervalInput(this.value)" onchange="intervalCommit(this.value)" disabled>
    </div>
    <div class="divider"></div>
    <div id="previewWrap">
      <div id="previewBox">
        <img id="previewImgA" src="" alt="">
        <img id="previewImgB" src="" alt="">
        <div id="previewPlaceholder">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2"/>
            <circle cx="8.5" cy="8.5" r="1.5"/>
            <path d="M21 15l-5-5L5 21"/>
            <line x1="3" y1="3" x2="21" y2="21"/>
          </svg>
          <span data-i18n="preview_none">No preview available</span>
        </div>
        <div id="previewCounter">0 / 0</div>
        <div id="previewRating"></div>
      </div>
      <div id="previewCaption"></div>
    </div>
    <div class="btn-row">
      <button class="play-btn" id="hudBtn" onclick="cmd('toggle-hud')" disabled>
        <img src="/icon_hud.svg">
        <span class="play-lbl" id="hudBtnLabel" data-i18n="btn_hud_show">Show Info Bar</span>
      </button>
      <button class="play-btn" id="exifBtn" onclick="cmd('toggle-exif')" disabled>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10" opacity="0.5"/>
          <line x1="12" y1="16" x2="12" y2="12"/>
          <line x1="12" y1="8" x2="12.01" y2="8"/>
        </svg>
        <span class="play-lbl" id="exifBtnLabel" data-i18n="btn_exif_show">Show Details</span>
      </button>
    </div>
  </div>
</div>

<!-- Picture Frame section (background mode only) -->
<div id="pfSection" style="display:none">

  <div id="pfWarning">
    <svg class="warn-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
      <line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17" stroke-width="3"/>
    </svg>
    <div>
      <div class="warn-title" data-i18n="pf_warn_title">No images available</div>
      <div class="warn-sub" data-i18n="pf_warn_sub">Check the folder path or filter settings.</div>
    </div>
  </div>

  <!-- SHOW CONTROL -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span data-i18n="lbl_show_control">Show Control</span></div>
    <div class="action-row">
      <button class="action-btn" id="pfStartBtn" onclick="pfStart()">
        <svg viewBox="0 0 16 16" fill="currentColor"><polygon points="3,1 14,8 3,15"/></svg>
        <span data-i18n="btn_start_show">Start Show</span>
      </button>
      <button class="action-btn" id="pfStopBtn" onclick="pfStop()" disabled>
        <svg viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="12" height="12" rx="2"/></svg>
        <span data-i18n="btn_end_show">End Show</span>
      </button>
    </div>
  </div>

  <div class="divider"></div>

  <!-- INTERVAL -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span data-i18n="lbl_interval">Interval</span></div>
    <div class="slider-block">
      <div class="slider-hdr">
        <span class="opt-title" data-i18n="opt_interval">Autoplay interval</span>
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
    <div class="opt-lbl"><div class="opt-bar"></div><span data-i18n="lbl_scale">Scale</span></div>
    <div class="opt-row">
      <span class="opt-title" data-i18n="opt_scale">Image scale</span>
      <div class="chip-group">
        <button class="chip" id="pfFitChip" onclick="pfScale('fit')">
          <img src="/icon_scale_fit.svg" alt=""><span data-i18n="chip_fit">Fit</span>
        </button>
        <button class="chip" id="pfFillChip" onclick="pfScale('fill')">
          <img src="/icon_scale_fill.svg" alt=""><span data-i18n="chip_fill">Fill</span>
        </button>
      </div>
    </div>
  </div>

  <div class="divider"></div>

  <!-- TRANSITION -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span data-i18n="lbl_transition">Transition</span></div>
    <div class="chip-group">
      <button class="chip" id="pfTransFadeChip" onclick="pfTransition('fade')">
        <img src="/icon_trans_fade.svg" alt=""><span data-i18n="chip_fade">Fade</span>
      </button>
      <button class="chip" id="pfTransSlideChip" onclick="pfTransition('slide')">
        <img src="/icon_trans_slide.svg" alt=""><span data-i18n="chip_slide">Slide</span>
      </button>
      <button class="chip" id="pfTransZoomChip" onclick="pfTransition('zoom')">
        <img src="/icon_trans_zoom.svg" alt=""><span data-i18n="chip_zoom">Zoom</span>
      </button>
      <button class="chip" id="pfTransFadeblackChip" onclick="pfTransition('fadeblack')">
        <img src="/icon_trans_fadeblack.svg" alt=""><span data-i18n="chip_fadeblack">Fade/Black</span>
      </button>
    </div>
  </div>

  <div class="divider"></div>

  <!-- RESCAN IN BACKGROUND -->
  <div class="opt-item">
    <div class="opt-lbl"><div class="opt-bar"></div><span data-i18n="lbl_rescan_bg">Rescan in Background</span></div>
    <div style="display:flex;gap:10px;align-items:center">
      <span class="opt-title" style="white-space:nowrap" data-i18n="btn_rescan_lbl">Rescan:</span>
      <select id="pfRescanSelect" onchange="pfRescanInterval(parseInt(this.value))" style="flex:1;margin-bottom:0">
        <option value="0"     data-i18n="chip_off">Off</option>
        <option value="300"  >5 min</option>
        <option value="600"  >10 min</option>
        <option value="1800" >30 min</option>
        <option value="3600" >1 h</option>
        <option value="10800">3 h</option>
        <option value="21600">6 h</option>
        <option value="32400">9 h</option>
        <option value="43200">12 h</option>
        <option value="86400">24 h</option>
      </select>
      <button class="action-btn" id="pfRescanBtn" onclick="pfRescan()" disabled style="flex:0 0 auto;padding:10px 16px">
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M13.5 8A5.5 5.5 0 1 1 8 2.5"/>
          <polyline points="11,1 14,4 11,7"/>
        </svg>
        <span data-i18n="btn_rescan">Scan Now</span>
      </button>
    </div>
  </div>

</div>

<footer>v__APP_VERSION__</footer>

<script>
  // ── i18n ─────────────────────────────────────────────────────────────
  var TRANS = __TRANSLATIONS_JSON__;
  var _appLang = '__LANGUAGE__';
  function _t(key) {
    var lang = _appLang === 'auto'
      ? (navigator.language || 'en').slice(0, 2)
      : _appLang;
    var dict = TRANS[lang] || TRANS['en'];
    return (dict && dict[key]) || TRANS['en'][key] || key;
  }
  function _applyI18n() {
    document.title = _t('title');
    document.querySelectorAll('[data-i18n]').forEach(function(el) {
      el.textContent = _t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-title]').forEach(function(el) {
      el.title = _t(el.getAttribute('data-i18n-title'));
    });
  }
  _applyI18n();

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

  // ── Transition chips ────────────────────────────────────────
  function pfTransition(mode) {
    fetch('/control/transition?value=' + mode).catch(function(){});
    updateTransitionChips(mode);
  }
  function updateTransitionChips(mode) {
    var map = {
      'fade':      'pfTransFadeChip',
      'slide':     'pfTransSlideChip',
      'zoom':      'pfTransZoomChip',
      'fadeblack': 'pfTransFadeblackChip',
    };
    Object.keys(map).forEach(function(m) {
      document.getElementById(map[m]).classList.toggle('active', mode === m);
    });
  }

  // ── Start / stop / rescan ───────────────────────────────────
  function pfStart()  { fetch('/control/start').catch(function(){}); setTimeout(poll, 300); }
  function pfStop()   { fetch('/control/stop').catch(function(){});  setTimeout(poll, 300); }
  function pfRescan() { fetch('/control/rescan').catch(function(){}); setTimeout(poll, 300); }

  // ── Rescan interval select ──────────────────────────────────
  function pfRescanInterval(secs) {
    fetch('/control/rescan-interval?value=' + secs).catch(function(){});
    document.getElementById('pfRescanSelect').value = secs;
  }
  function updateRescanSelect(secs) {
    document.getElementById('pfRescanSelect').value = secs;
  }

  // ── Tab switching ───────────────────────────────────────────
  function switchTab(tab) {
    document.getElementById('remoteSection').style.display = tab === 'remote'   ? '' : 'none';
    document.getElementById('pfSection').style.display     = tab === 'picframe' ? '' : 'none';
    document.getElementById('tabRemote').classList.toggle('active',   tab === 'remote');
    document.getElementById('tabPicframe').classList.toggle('active', tab === 'picframe');
    try { localStorage.setItem('ps_tab', tab); } catch(e) {}
  }

  // ── Remote-tab interval slider (1–99 s) ─────────────────────
  var _ivCommitTimer = null;
  function intervalInput(v) {
    document.getElementById('intervalLabel').textContent = v + 's';
    sliderFill(document.getElementById('intervalSlider'));
    clearTimeout(_ivCommitTimer);
    _ivCommitTimer = setTimeout(function() { intervalCommit(v); }, 600);
  }
  function intervalCommit(v) {
    clearTimeout(_ivCommitTimer);
    fetch('/interval?value=' + (parseInt(v) * 1000)).catch(function(){});
  }

  // ── Standard remote ─────────────────────────────────────────
  function cmd(action) {
    fetch('/' + action).catch(function(){});
    setTimeout(poll, 300);
  }

  // ── Polling ───────────────────────────────────────────────
  var _bgMode     = __BACKGROUND_MODE__;
  var _firstPoll  = true;
  var _online     = true;
  var _lastIndex  = -1;

  if (_bgMode) {
    document.getElementById('tabBar').style.display = '';
    try {
      var _savedTab = localStorage.getItem('ps_tab');
      if (_savedTab === 'picframe') switchTab('picframe');
    } catch(e) {}
  }

  function setOffline() {
    if (!_online) return;
    _online = false;
    ['prevBtn', 'nextBtn', 'playBtn', 'hudBtn', 'exifBtn', 'intervalSlider'].forEach(function(id) {
      document.getElementById(id).disabled = true;
    });
    document.getElementById('intervalWrap').classList.add('disabled');
    ['previewImgA', 'previewImgB'].forEach(function(id) {
      var im = document.getElementById(id);
      im.classList.remove('loaded');
      im.removeAttribute('src');
    });
    document.getElementById('previewBox').classList.remove('active');
    document.getElementById('previewCaption').textContent = '';
    _lastIndex = -1;
    if (_bgMode) {
      ['pfStartBtn', 'pfStopBtn', 'pfRescanBtn',
       'pfIntervalSlider', 'pfFitChip', 'pfFillChip',
       'pfTransFadeChip', 'pfTransSlideChip', 'pfTransZoomChip', 'pfTransFadeblackChip',
       'pfRescanSelect'].forEach(
        function(id) { document.getElementById(id).disabled = true; }
      );
    }
    document.getElementById('status').style.color = '#fcd34d';
    document.getElementById('status').textContent  = _t('status_offline');
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
        var navEnabled = active && total > 0;
        document.getElementById('prevBtn').disabled = !navEnabled;
        document.getElementById('nextBtn').disabled = !navEnabled;
        document.getElementById('playBtn').disabled = !navEnabled;
        var previewBox = document.getElementById('previewBox');
        var imgA = document.getElementById('previewImgA');
        var imgB = document.getElementById('previewImgB');
        if (navEnabled) {
          if (d.index !== _lastIndex) {
            // Cross-fade: load into whichever <img> is currently hidden,
            // then swap .loaded classes when the new image is ready so both
            // fades run in lockstep for a clean, fixed-duration 700 ms swap.
            var next = imgA.classList.contains('loaded') ? imgB : imgA;
            var curr = imgA.classList.contains('loaded') ? imgA : imgB;
            next.onload = function() {
              next.classList.add('loaded');
              curr.classList.remove('loaded');
              previewBox.classList.add('active');
            };
            next.onerror = function() {};
            next.src = '/preview?t=' + Date.now();
            _lastIndex = d.index;
          }
          document.getElementById('previewCounter').textContent =
            (d.index + 1) + ' / ' + total;
          var r = Math.max(0, Math.min(5, d.rating | 0));
          var ratingHtml = '';
          for (var i = 1; i <= 5; i++) {
            ratingHtml += '<span class="' + (i <= r ? 'star-on' : 'star-off') + '">★</span>';
          }
          document.getElementById('previewRating').innerHTML = ratingHtml;
          var capText = (d.caption && d.caption.length > 0)
            ? d.caption
            : _t('caption_empty');
          document.getElementById('previewCaption').textContent =
            _t('caption_prefix') + ' ' + capText;
        } else {
          imgA.classList.remove('loaded');
          imgA.removeAttribute('src');
          imgB.classList.remove('loaded');
          imgB.removeAttribute('src');
          previewBox.classList.remove('active');
          document.getElementById('previewCaption').textContent = '';
          _lastIndex = -1;
        }
        document.getElementById('status').textContent = active && total > 0
          ? _t('status_photo').replace('{n}', d.index + 1).replace('{total}', total) +
            '\u2002(' + (playing ? _t('status_playing') : _t('status_paused')) + ')'
          : _t('status_waiting');
        document.getElementById('playBtnIcon').src =
          playing ? '/icon_pause.svg' : '/icon_play.svg';
        document.getElementById('playBtnLabel').textContent =
          playing ? _t('play_pause') : _t('play_play');
        document.getElementById('hudBtn').disabled = !active;
        document.getElementById('hudBtnLabel').textContent =
          d.hud_visible ? _t('btn_hud_hide') : _t('btn_hud_show');
        document.getElementById('exifBtn').disabled = !active;
        document.getElementById('exifBtnLabel').textContent =
          d.exif_visible ? _t('btn_exif_hide') : _t('btn_exif_show');

        // Interval slider — only changeable while autoplay is OFF
        var ivSlider = document.getElementById('intervalSlider');
        ivSlider.disabled = !active || playing;
        document.getElementById('intervalWrap').classList.toggle('disabled', ivSlider.disabled);
        if (!ivSlider.matches(':active')) {
          var s = Math.max(1, Math.min(99, Math.round(d.interval / 1000)));
          if (parseInt(ivSlider.value) !== s) {
            ivSlider.value = s;
            document.getElementById('intervalLabel').textContent = s + 's';
          }
          sliderFill(ivSlider);
        }

        // Picture Frame section
        if (_bgMode) {
          var ss = d.show_started;
          document.getElementById('pfStartBtn').disabled  = ss;
          document.getElementById('pfStopBtn').disabled   = !ss;
          // Rescan only available in standby (not while show runs or scan in progress)
          document.getElementById('pfRescanBtn').disabled    = ss || scanning;
          document.getElementById('pfRescanSelect').disabled = ss;
          document.getElementById('pfIntervalSlider').disabled = false;
          document.getElementById('pfFitChip').disabled   = false;
          document.getElementById('pfFillChip').disabled  = false;
          document.getElementById('pfTransFadeChip').disabled      = false;
          document.getElementById('pfTransSlideChip').disabled     = false;
          document.getElementById('pfTransZoomChip').disabled      = false;
          document.getElementById('pfTransFadeblackChip').disabled = false;

          document.getElementById('pfWarning').style.display =
            (!scanning && total === 0) ? 'flex' : 'none';

          var slider = document.getElementById('pfIntervalSlider');
          if (_firstPoll || !slider.matches(':active')) {
            var idx = msToSlider(d.interval);
            slider.value = idx;
            document.getElementById('pfIntervalLabel').textContent =
              fmtSeconds(STEPS[idx]);
            sliderFill(slider);
          }
          updateScaleChips(d.scale);
          updateTransitionChips(d.transition);
          if (_firstPoll) updateRescanSelect(d.rescan_interval || 0);
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
    startShowRequested           = Signal()     # /control/start received
    stopShowRequested            = Signal()     # /control/stop received
    intervalChangeRequested      = Signal(int)  # /control/interval — ms value
    scaleChangeRequested         = Signal(str)  # /control/scale — "fit" | "fill"
    transitionChangeRequested    = Signal(str)  # /control/transition — "fade"|"slide"|"zoom"|"fadeblack"
    rescanRequested              = Signal()     # /control/rescan received
    rescanIntervalChangeRequested = Signal(int) # /control/rescan-interval — seconds (0=off)
    toggleExifRequested          = Signal()     # /toggle-exif received (QML toggles the EXIF panel)
    showStartedChanged           = Signal()     # show_started flag changed (QML binding)
    exifVisibleChanged           = Signal()     # exif panel visibility (QML → remote)

    # ── Internal cross-thread signals (preview generation) ─────────────────────
    # Worker threads emit these; the connected slots run on the main Qt thread
    # (Qt.QueuedConnection auto-marshalling) so QTcpSocket writes stay on the
    # thread that owns the socket. This keeps Pillow off the UI thread, so the
    # slideshow's own fade animations don't stutter while generating previews.
    _previewReady   = Signal(object, bytes)     # (sock, jpeg_bytes)
    _previewFailed  = Signal(object)            # (sock,)

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
        self._exif_visible    = False   # mirrored from QML (SlideshowPage._exifVisible)
        self._rescan_interval = 0       # auto-rescan interval in seconds (0 = off)
        self._server          = QTcpServer(self)
        self._clients: list[QTcpSocket] = []
        self._server.newConnection.connect(self._on_new_connection)

        # Preview cache (bytes for the most recently generated thumbnail).
        # Keyed by absolute file path so the same image is never re-encoded
        # across multiple /preview hits.
        self._preview_lock         = threading.Lock()
        self._preview_cache_path   = ""
        self._preview_cache_data: bytes | None = None
        self._previewReady.connect(self._send_preview_ok)
        self._previewFailed.connect(self._send_preview_err)

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

    @Property(bool, notify=exifVisibleChanged)
    def exifVisible(self) -> bool:
        return self._exif_visible

    @Slot(bool)
    def setExifVisible(self, visible: bool) -> None:
        if self._exif_visible == visible:
            return
        self._exif_visible = visible
        self.exifVisibleChanged.emit()

    @Slot(int)
    def setRescanInterval(self, secs: int) -> None:
        self._rescan_interval = secs

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
        sock.deleteLater()

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
        sock.abort()  # hard close — avoids TIME_WAIT accumulation under high poll rate

    def _json_ok(self, sock: QTcpSocket) -> None:
        self._respond(sock, "200 OK", "application/json", '{"ok":true}')

    def _json_error(self, sock: QTcpSocket, msg: str, status: str = "400 Bad Request") -> None:
        body = json.dumps({"error": msg})
        self._respond(sock, status, "application/json", body)

    # ── Preview generation (worker thread + signal back to main thread) ────────
    def _gen_preview_async(self, sock: QTcpSocket, path: str) -> None:
        """Worker-thread entry: produce a JPEG thumbnail, then emit a signal."""
        with self._preview_lock:
            if self._preview_cache_path == path and self._preview_cache_data:
                self._previewReady.emit(sock, self._preview_cache_data)
                return
        try:
            from PIL import Image, ImageOps
            img = Image.open(path)
            img = ImageOps.exif_transpose(img)
            if img.mode not in ("RGB", "L"):
                img = img.convert("RGB")
            img.thumbnail((800, 800), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=75, optimize=True)
            data = buf.getvalue()
        except Exception:
            self._previewFailed.emit(sock)
            return
        with self._preview_lock:
            self._preview_cache_path = path
            self._preview_cache_data = data
        self._previewReady.emit(sock, data)

    @Slot(object, bytes)
    def _send_preview_ok(self, sock: QTcpSocket, data: bytes) -> None:
        if sock not in self._clients:
            return  # client disconnected before we finished encoding
        try:
            self._respond(sock, "200 OK", "image/jpeg", data)
        except RuntimeError:
            pass  # underlying C++ socket was deleted

    @Slot(object)
    def _send_preview_err(self, sock: QTcpSocket) -> None:
        if sock not in self._clients:
            return
        try:
            self._respond(sock, "500 Internal Server Error", "text/plain", "preview unavailable")
        except RuntimeError:
            pass

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
                bg_js    = "true" if self._background_mode else "false"
                trans_js = json.dumps(_TRANSLATIONS, ensure_ascii=False)
                lang     = self._controller.language
                html     = (
                    _REMOTE_HTML
                    .replace("__APP_VERSION__", self._version)
                    .replace("__BACKGROUND_MODE__", bg_js)
                    .replace("__TRANSLATIONS_JSON__", trans_js)
                    .replace("__LANGUAGE__", lang)
                )
                self._respond(sock, "200 OK", "text/html; charset=utf-8", html)
            case "/logo.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("logo.svg"))
            case "/icon_play.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_play.svg"))
            case "/icon_pause.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_pause.svg"))
            case "/icon_hud.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_hud_fundamental.svg"))
            case "/icon_scale_fit.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_scale_fit.svg"))
            case "/icon_scale_fill.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_scale_fill.svg"))
            case "/icon_trans_fade.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_trans_fade.svg"))
            case "/icon_trans_slide.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_trans_slide.svg"))
            case "/icon_trans_zoom.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_trans_zoom.svg"))
            case "/icon_trans_fadeblack.svg":
                self._respond(sock, "200 OK", "image/svg+xml", _read_img("icon_trans_fadeblack.svg"))

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
            case "/toggle-hud":
                ctrl.setHudVisible(not ctrl.hudVisible)
                self._respond(sock, "200 OK", "text/plain", "ok")
            case "/interval":
                try:
                    ms = int(qs.get("value", [""])[0])
                except (ValueError, IndexError):
                    self._json_error(sock, "missing or invalid 'value' parameter")
                    return
                if not (1_000 <= ms <= 99_000):
                    self._json_error(sock, "value out of range (1000–99000 ms)")
                    return
                ctrl.setInterval(ms)
                self._json_ok(sock)
            case "/toggle-exif":
                self.toggleExifRequested.emit()
                self._respond(sock, "200 OK", "text/plain", "ok")
            case "/preview":
                path = ctrl.currentImagePath()
                if not path:
                    self._respond(sock, "404 Not Found", "text/plain", "no image")
                    return
                # Off-thread: heavy Pillow work would otherwise block the Qt
                # event loop and stutter the slideshow's own fade animations.
                threading.Thread(
                    target=self._gen_preview_async,
                    args=(sock, path),
                    daemon=True,
                ).start()
                # No response here — the worker emits a signal which the slot
                # delivers on the main thread.
            case "/status":
                body = json.dumps({
                    "index":        ctrl.currentIndex,
                    "total":        ctrl.imageCount,
                    "playing":      ctrl.isPlaying,
                    "active":       self._show_active,
                    "scanning":     ctrl.scanning,
                    "hud_visible":  ctrl.hudVisible,
                    "exif_visible": self._exif_visible,
                    "caption":      ctrl.imageCaption(ctrl.currentIndex) if ctrl.imageCount > 0 else "",
                    "rating":       ctrl.imageRating(ctrl.currentIndex)  if ctrl.imageCount > 0 else 0,
                    # background mode fields (always present for simplicity)
                    "background_mode":  self._background_mode,
                    "show_started":     self._show_started,
                    "interval":         ctrl.interval,
                    "scale":            "fill" if ctrl.imageFill else "fit",
                    "transition":       ctrl.transitionStyle,
                    "rescan_interval":  self._rescan_interval,
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

            case "/control/transition":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                else:
                    value = qs.get("value", [""])[0]
                    if value not in ("fade", "slide", "zoom", "fadeblack"):
                        self._json_error(sock, "value must be one of: fade, slide, zoom, fadeblack")
                        return
                    self.transitionChangeRequested.emit(value)
                    self._json_ok(sock)

            case "/control/rescan":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                elif self._show_started:
                    self._json_error(sock, "cannot rescan while show is running", "409 Conflict")
                else:
                    self.rescanRequested.emit()
                    self._json_ok(sock)

            case "/control/rescan-interval":
                if not self._background_mode:
                    self._json_error(sock, "not in background mode", "404 Not Found")
                else:
                    try:
                        secs = int(qs.get("value", [""])[0])
                    except (ValueError, IndexError):
                        self._json_error(sock, "missing or invalid 'value' parameter")
                        return
                    valid = {0, 300, 600, 1800, 3600, 10800, 21600, 32400, 43200, 86400}
                    if secs not in valid:
                        self._json_error(sock, "value must be one of: " + ", ".join(str(v) for v in sorted(valid)))
                        return
                    self.rescanIntervalChangeRequested.emit(secs)
                    self._json_ok(sock)

            # ── reserved for future schedule API ─────────────────────────
            # /control/schedule/* routes will be added here
            case p if p.startswith("/control/schedule"):
                self._json_error(sock, "schedule API not yet implemented", "501 Not Implemented")

            case _:
                self._respond(sock, "404 Not Found", "text/plain", "not found")
