# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for main._parse_args() — CLI argument parsing.

All tests monkeypatch sys.argv and call _parse_args() directly.
No Qt application or display is required.
"""
from __future__ import annotations

import sys

import pytest

from main import _parse_args


def parse(args: list[str]):
    """Run _parse_args with the given argument list (sys.argv[1:] equivalent)."""
    sys.argv = ["picture-show3"] + args
    return _parse_args()


# ── Positional folder / mode detection ───────────────────────────────────────

class TestModeDetection:
    def test_no_args_all_none(self):
        kiosk, start, bg, fs, ov, *_ = parse([])
        assert kiosk is None
        assert start is None
        assert bg is None
        assert fs is False
        assert ov == {}

    def test_positional_folder_is_jump_start(self):
        kiosk, start, bg, *_ = parse(["/some/folder"])
        assert kiosk is None
        assert start == "/some/folder"
        assert bg is None

    def test_kiosk_flag_assigns_kiosk_folder(self):
        kiosk, start, bg, *_ = parse(["--kiosk", "/some/folder"])
        assert kiosk == "/some/folder"
        assert start is None
        assert bg is None

    def test_kiosk_without_folder_gives_none(self):
        kiosk, start, bg, *_ = parse(["--kiosk"])
        assert kiosk is None
        assert start is None
        assert bg is None

    def test_background_flag_assigns_background_folder(self):
        kiosk, start, bg, *_ = parse(["--background", "/some/folder"])
        assert kiosk is None
        assert start is None
        assert bg == "/some/folder"

    def test_background_without_folder_exits(self):
        with pytest.raises(SystemExit):
            parse(["--background"])

    def test_kiosk_and_background_mutually_exclusive(self):
        with pytest.raises(SystemExit):
            parse(["--kiosk", "--background", "/some/folder"])

    def test_fullscreen_sets_force_flag(self):
        _, _, _, fs, *_ = parse(["--fullscreen"])
        assert fs is True

    def test_fullscreen_not_in_overrides(self):
        # --fullscreen is handled separately, not via the overrides dict
        _, _, _, _, ov, *_ = parse(["--fullscreen"])
        assert "window/fullscreen" not in ov


# ── Unknown flags forwarded to Qt ─────────────────────────────────────────────

class TestQtArgvForwarding:
    def test_unknown_flag_forwarded(self):
        # parse_known_args cannot know --platform takes a value, so use = form
        # so both the flag and its value stay together as one unknown token.
        _, _, _, _, _, qt_argv, *_ = parse(["--platform=offscreen"])
        assert "--platform=offscreen" in qt_argv

    def test_known_flags_not_forwarded(self):
        _, _, _, _, _, qt_argv, *_ = parse(["--recursive", "--loop", "/folder"])
        # Only sys.argv[0] should be in qt_argv (no known flags, folder is positional)
        assert "--recursive" not in qt_argv
        assert "--loop" not in qt_argv


# ── Autoplay ──────────────────────────────────────────────────────────────────

class TestAutoplay:
    def test_autoplay_without_n_enables_but_keeps_interval(self):
        _, _, _, _, ov, *_ = parse(["--autoplay"])
        assert ov["autoplay"] is True
        assert "interval" not in ov

    def test_autoplay_with_n_sets_interval_ms(self):
        _, _, _, _, ov, *_ = parse(["--autoplay", "5"])
        assert ov["autoplay"] is True
        assert ov["interval"] == 5000

    def test_autoplay_with_n_1(self):
        _, _, _, _, ov, *_ = parse(["--autoplay", "1"])
        assert ov["interval"] == 1000

    def test_autoplay_with_n_99(self):
        _, _, _, _, ov, *_ = parse(["--autoplay", "99"])
        assert ov["interval"] == 99000

    def test_autoplay_large_value_not_clamped(self):
        # CLI values are session-only and never saved, so no clamping is applied
        _, _, _, _, ov, *_ = parse(["--autoplay", "6000"])
        assert ov["interval"] == 6_000_000  # 6000 s in ms

    def test_no_autoplay_flag_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "autoplay" not in ov


# ── Transition ────────────────────────────────────────────────────────────────

class TestTransition:
    @pytest.mark.parametrize("style", ["fade", "slide", "zoom", "fadeblack"])
    def test_valid_transition_style(self, style):
        _, _, _, _, ov, *_ = parse(["--transition", style])
        assert ov["transition"] == style

    def test_invalid_transition_exits(self):
        with pytest.raises(SystemExit):
            parse(["--transition", "wipe"])

    def test_no_transition_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "transition" not in ov


# ── Transition duration ───────────────────────────────────────────────────────

class TestTransitionDuration:
    def test_transition_dur_stored_as_ms(self):
        _, _, _, _, ov, *_ = parse(["--transition-dur", "800"])
        assert ov["transitionDuration"] == 800

    def test_transition_dur_any_positive_value_accepted(self):
        _, _, _, _, ov, *_ = parse(["--transition-dur", "10000"])
        assert ov["transitionDuration"] == 10000

    def test_transition_dur_small_value_not_clamped(self):
        _, _, _, _, ov, *_ = parse(["--transition-dur", "50"])
        assert ov["transitionDuration"] == 50

    def test_no_transition_dur_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "transitionDuration" not in ov


# ── Sort ──────────────────────────────────────────────────────────────────────

class TestSort:
    @pytest.mark.parametrize("order", ["name", "date", "random"])
    def test_valid_sort_orders(self, order):
        _, _, _, _, ov, *_ = parse(["--sort", order])
        assert ov["sort"] == order

    def test_invalid_sort_exits(self):
        with pytest.raises(SystemExit):
            parse(["--sort", "size"])

    def test_no_sort_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "sort" not in ov


# ── Image scale ───────────────────────────────────────────────────────────────

class TestScale:
    def test_scale_fit_sets_image_fill_false(self):
        _, _, _, _, ov, *_ = parse(["--scale", "fit"])
        assert ov["imageFill"] is False

    def test_scale_fill_sets_image_fill_true(self):
        _, _, _, _, ov, *_ = parse(["--scale", "fill"])
        assert ov["imageFill"] is True

    def test_invalid_scale_exits(self):
        with pytest.raises(SystemExit):
            parse(["--scale", "stretch"])

    def test_no_scale_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "imageFill" not in ov


# ── Auto panorama ─────────────────────────────────────────────────────────────

class TestAutoPanorama:
    def test_auto_panorama_enables(self):
        _, _, _, _, ov, *_ = parse(["--auto-panorama"])
        assert ov["autoPanorama"] is True

    def test_no_auto_panorama_disables(self):
        _, _, _, _, ov, *_ = parse(["--no-auto-panorama"])
        assert ov["autoPanorama"] is False

    def test_no_flag_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "autoPanorama" not in ov


# ── Recursive ────────────────────────────────────────────────────────────────

class TestRecursive:
    def test_recursive_flag_sets_override(self):
        _, _, _, _, ov, *_ = parse(["--recursive"])
        assert ov["recursive"] is True

    def test_no_recursive_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "recursive" not in ov


# ── Loop ─────────────────────────────────────────────────────────────────────

class TestLoop:
    def test_loop_enables(self):
        _, _, _, _, ov, *_ = parse(["--loop"])
        assert ov["loop"] is True

    def test_no_loop_disables(self):
        _, _, _, _, ov, *_ = parse(["--no-loop"])
        assert ov["loop"] is False

    def test_no_flag_not_in_overrides(self):
        _, _, _, _, ov, *_ = parse([])
        assert "loop" not in ov


# ── Combined / integration ────────────────────────────────────────────────────

class TestCombined:
    def test_kiosk_with_all_show_options(self):
        kiosk, start, bg, fs, ov, *_ = parse([
            "--kiosk", "--recursive", "--fullscreen",
            "--autoplay", "3", "--loop",
            "--transition", "zoom",
            "--transition-dur", "400",
            "--sort", "date",
            "--scale", "fill",
            "--auto-panorama",
            "/photos",
        ])
        assert kiosk == "/photos"
        assert start is None
        assert bg is None
        assert fs is True
        assert ov["autoplay"] is True
        assert ov["interval"] == 3000
        assert ov["transition"] == "zoom"
        assert ov["transitionDuration"] == 400
        assert ov["sort"] == "date"
        assert ov["imageFill"] is True
        assert ov["autoPanorama"] is True
        assert ov["recursive"] is True
        assert ov["loop"] is True

    def test_jump_start_with_show_options(self):
        kiosk, start, bg, fs, ov, *_ = parse([
            "--autoplay", "10", "--transition", "fade",
            "--sort", "random", "--no-loop",
            "/mnt/photos",
        ])
        assert kiosk is None
        assert start == "/mnt/photos"
        assert bg is None
        assert fs is False
        assert ov["autoplay"] is True
        assert ov["interval"] == 10000
        assert ov["transition"] == "fade"
        assert ov["sort"] == "random"
        assert ov["loop"] is False

    def test_background_with_show_options(self):
        kiosk, start, bg, fs, ov, *_ = parse([
            "--background", "--autoplay", "30", "--fullscreen",
            "--sort", "date", "--scale", "fill",
            "/mnt/photos",
        ])
        assert kiosk is None
        assert start is None
        assert bg == "/mnt/photos"
        assert fs is True
        assert ov["autoplay"] is True
        assert ov["interval"] == 30000
        assert ov["sort"] == "date"
        assert ov["imageFill"] is True


# ── On-show hooks (--on-show-start / --on-show-stop) ─────────────────────────

class TestOnShowHooks:
    def test_on_show_start_captured(self):
        *_, on_start, on_stop = parse(["--background", "--on-show-start", "display_on.sh", "/folder"])
        assert on_start == "display_on.sh"
        assert on_stop is None

    def test_on_show_stop_captured(self):
        *_, on_start, on_stop = parse(["--background", "--on-show-stop", "display_off.sh", "/folder"])
        assert on_start is None
        assert on_stop == "display_off.sh"

    def test_both_hooks_captured(self):
        *_, on_start, on_stop = parse([
            "--background",
            "--on-show-start", "display_on.sh",
            "--on-show-stop",  "display_off.sh",
            "/folder",
        ])
        assert on_start == "display_on.sh"
        assert on_stop == "display_off.sh"

    def test_no_hooks_gives_none(self):
        *_, on_start, on_stop = parse(["--background", "/folder"])
        assert on_start is None
        assert on_stop is None

    def test_hooks_without_background_warn(self, capsys):
        parse(["--on-show-start", "display_on.sh"])
        assert "--on-show-start" in capsys.readouterr().err
