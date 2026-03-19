// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
pragma Singleton
import QtQuick

// ─────────────────────────────────────────────────────────────────────────────
// Central color palette for picture-show3
//
// Usage (after registering as singleton or adding to qmldir):
//   import "." as Local
//   color: Local.Theme.surface
// ─────────────────────────────────────────────────────────────────────────────
QtObject {

    // ── Backgrounds (dark → mid) ─────────────────────────────────────────────
    readonly property color bgDeep:      "#111820"  // window bg, input fill
    readonly property color bgGradEnd:   "#111820"  // settings page gradient end
    readonly property color bgCard:      "#131e2a"  // card + popup background
    readonly property color surface:     "#1e293a"  // raised elements: buttons, dividers, toggle-off
    readonly property color surfaceHover:"#293952"  // hover state on surface elements
    readonly property color borderMuted: "#252c40"  // inactive input border

    // ── Accent — blueish scale ────────────────────────────────────────────────
    readonly property color accentDeep:  "#20293d"  // selected chip background
    readonly property color accentPress: "#32405e"  // primary button pressed / active input border
    readonly property color accent:      "#526796"  // primary accent: button, slider fill, toggle-on
    readonly property color accentLight: "#96a5c5"  // light accent: browse label, slider handle, value text

    // ── Text ─────────────────────────────────────────────────────────────────
    readonly property color textPrimary:  "#e2e8f0"  // headings, values, primary labels
    readonly property color textSecondary:"#94a3b8"  // secondary labels, HUD body text
    readonly property color textSubtle:   "#64748b"  // HUD icons, tertiary info
    readonly property color textMuted:    "#475569"  // section labels, captions
    readonly property color textDisabled: "#6d84a5"  // disabled button text, HUD separators
    readonly property color textGhost:    "#6e6e85"  // keyboard hint line (barely visible)

    // ── Misc ─────────────────────────────────────────────────────────────────
    readonly property color starInactive:  "#30303b"  // disabled star for rating

    // ── Status ───────────────────────────────────────────────────────────────
    readonly property color statusOk:   "#34d399"  // ✓ images found
    readonly property color statusWarn: "#f59e0b"  // ⚠ no images found
}
