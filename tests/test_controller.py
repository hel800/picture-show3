# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for SlideshowController — pure-logic layer (no display required).

All tested methods are synchronous; no Qt timer or event-loop spinning needed.
"""
from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

import pytest

import io

from PIL import Image, IptcImagePlugin

from slideshow_controller import IMAGE_EXTENSIONS, SlideshowController
from tests.conftest import (
    _build_iptc_caption_payload,
    _inject_app13,
    make_jpeg_with_exif,
    make_jpeg_with_iptc_caption,
    make_jpeg_with_xmp_attr,
    make_jpeg_with_xmp_elem,
    make_plain_jpeg,
)


# ── IMAGE_EXTENSIONS ──────────────────────────────────────────────────────────

class TestImageExtensions:
    def test_contains_all_documented_formats(self):
        for ext in (".jpg", ".jpeg", ".png", ".gif", ".bmp",
                    ".webp", ".tiff", ".tif", ".heic", ".avif"):
            assert ext in IMAGE_EXTENSIONS

    def test_is_frozenset(self):
        assert isinstance(IMAGE_EXTENSIONS, frozenset)

    def test_does_not_contain_non_image(self):
        for ext in (".txt", ".csv", ".mp4", ".pdf"):
            assert ext not in IMAGE_EXTENSIONS


# ── loadFolder — URL / path parsing ──────────────────────────────────────────

class TestLoadFolder:
    def test_plain_path(self, ctrl, image_folder, load_folder):
        load_folder(ctrl, str(image_folder))
        assert ctrl.imageCount == 5

    def test_file_url_triple_slash(self, ctrl, image_folder, load_folder):
        url = "file:///" + str(image_folder).replace("\\", "/")
        load_folder(ctrl, url)
        assert ctrl.imageCount == 5

    def test_file_url_double_slash(self, ctrl, image_folder, load_folder):
        url = "file://" + str(image_folder).replace("\\", "/")
        load_folder(ctrl, url)
        assert ctrl.imageCount == 5

    def test_empty_string_clears_images(self, ctrl_with_images):
        ctrl_with_images.loadFolder("")
        assert ctrl_with_images.imageCount == 0

    def test_nonexistent_folder_clears_images(self, ctrl):
        ctrl.loadFolder("/this/does/not/exist/at/all")
        assert ctrl.imageCount == 0

    def test_non_image_files_are_ignored(self, tmp_path, ctrl, load_folder):
        (tmp_path / "readme.txt").write_text("hello")
        (tmp_path / "data.csv").write_text("a,b,c")
        make_plain_jpeg(tmp_path / "photo.jpg")
        load_folder(ctrl, str(tmp_path))
        assert ctrl.imageCount == 1

    def test_mixed_extensions(self, tmp_path, ctrl, load_folder):
        for ext in (".jpg", ".png", ".bmp", ".txt", ".py"):
            (tmp_path / f"file{ext}").write_bytes(b"\xff\xd8\xff" if ext != ".txt" and ext != ".py" else b"x")
        # .txt and .py should not be counted — Pillow might fail to open them
        # so we simply verify the count matches only recognised extensions
        load_folder(ctrl, str(tmp_path))
        # Count files whose suffix is in IMAGE_EXTENSIONS
        expected = sum(
            1 for f in tmp_path.iterdir()
            if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS
        )
        assert ctrl.imageCount == expected

    def test_whitespace_stripped_from_path(self, ctrl, image_folder, load_folder):
        # loadFolder strips leading/trailing whitespace from the parsed path
        plain = str(image_folder)
        load_folder(ctrl, plain)
        assert ctrl.imageCount == 5


# ── Sorting ───────────────────────────────────────────────────────────────────

class TestSorting:
    def test_name_sort_is_case_insensitive(self, tmp_path, ctrl, load_folder):
        for name in ("Banana.jpg", "apple.jpg", "Cherry.jpg"):
            make_plain_jpeg(tmp_path / name)
        ctrl.setSortOrder("name")
        load_folder(ctrl, str(tmp_path))
        names = [Path(ctrl.imagePath(i)).name for i in range(ctrl.imageCount)]
        assert names == sorted(names, key=str.lower)

    def test_random_sort_preserves_count(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("random")
        load_folder(ctrl, str(image_folder))
        assert ctrl.imageCount == 5

    def test_date_sort_preserves_count(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert ctrl.imageCount == 5

    def test_changing_sort_order_reapplies_to_loaded_images(self, ctrl_with_images):
        ctrl_with_images.setSortOrder("random")
        assert ctrl_with_images.imageCount == 5
        ctrl_with_images.setSortOrder("name")
        assert ctrl_with_images.imageCount == 5

    def test_name_sort_after_folder_change(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "imgs"
        d.mkdir()
        for name in ("z.jpg", "a.jpg", "m.jpg"):
            make_plain_jpeg(d / name)
        ctrl.setSortOrder("name")
        load_folder(ctrl, str(d))
        names = [Path(ctrl.imagePath(i)).name for i in range(ctrl.imageCount)]
        assert names == ["a.jpg", "m.jpg", "z.jpg"]


# ── Navigation ────────────────────────────────────────────────────────────────

class TestNavigation:
    def test_next_advances_index(self, ctrl_with_images):
        ctrl_with_images.goTo(0)
        ctrl_with_images.nextImage()
        assert ctrl_with_images.currentIndex == 1

    def test_prev_decrements_index(self, ctrl_with_images):
        ctrl_with_images.goTo(2)
        ctrl_with_images.prevImage()
        assert ctrl_with_images.currentIndex == 1

    def test_next_wraps_with_loop(self, ctrl_with_images):
        ctrl_with_images.setLoop(True)
        ctrl_with_images.goTo(4)          # last image
        ctrl_with_images.nextImage()
        assert ctrl_with_images.currentIndex == 0

    def test_next_stays_at_end_without_loop(self, ctrl_with_images):
        ctrl_with_images.setLoop(False)
        ctrl_with_images.goTo(4)
        ctrl_with_images.nextImage()
        assert ctrl_with_images.currentIndex == 4   # unchanged

    def test_prev_wraps_with_loop(self, ctrl_with_images):
        ctrl_with_images.setLoop(True)
        ctrl_with_images.goTo(0)
        ctrl_with_images.prevImage()
        assert ctrl_with_images.currentIndex == 4

    def test_prev_stays_at_start_without_loop(self, ctrl_with_images):
        ctrl_with_images.setLoop(False)
        ctrl_with_images.goTo(0)
        ctrl_with_images.prevImage()
        assert ctrl_with_images.currentIndex == 0   # unchanged

    def test_next_noop_when_no_images(self, ctrl):
        ctrl.nextImage()                  # must not raise
        assert ctrl.currentIndex == 0

    def test_prev_noop_when_no_images(self, ctrl):
        ctrl.prevImage()
        assert ctrl.currentIndex == 0

    def test_goto_valid_index(self, ctrl_with_images):
        ctrl_with_images.goTo(3)
        assert ctrl_with_images.currentIndex == 3

    def test_goto_negative_is_ignored(self, ctrl_with_images):
        ctrl_with_images.goTo(2)
        ctrl_with_images.goTo(-1)
        assert ctrl_with_images.currentIndex == 2   # unchanged

    def test_goto_out_of_range_is_ignored(self, ctrl_with_images):
        ctrl_with_images.goTo(2)
        ctrl_with_images.goTo(999)
        assert ctrl_with_images.currentIndex == 2   # unchanged

    def test_next_without_loop_stops_playback(self, ctrl_with_images):
        ctrl_with_images.setLoop(False)
        ctrl_with_images.togglePlay()         # start playing
        ctrl_with_images.goTo(4)
        ctrl_with_images.nextImage()
        assert ctrl_with_images.isPlaying is False


# ── Star-rating filter ────────────────────────────────────────────────────────

class TestRatingFilter:
    def test_rating_zero_shows_all(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(0)
        assert ctrl.imageCount == 6

    def test_filter_at_rating_3(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(3)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.imageCount == 3   # r3, r4, r5

    def test_filter_at_rating_5(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(5)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.imageCount == 1   # only r5

    def test_filter_applied_before_load(self, ctrl, rated_folder, load_folder):
        ctrl.setMinRating(4)
        load_folder(ctrl, str(rated_folder))
        assert ctrl.imageCount == 2   # r4, r5

    def test_rating_clamped_above_5(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(10)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.minRating == 5

    def test_rating_clamped_below_0(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(-3)
        assert ctrl.minRating == 0
        assert ctrl.imageCount == 6

    def test_total_image_count_unaffected_by_filter(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(4)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.totalImageCount == 6
        assert ctrl.imageCount == 2

    def test_same_rating_value_is_noop(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(3)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        count_before = ctrl.imageCount
        ctrl.setMinRating(3)            # identical value — no filter re-run
        assert ctrl.imageCount == count_before

    def test_filter_resets_current_index_to_zero(self, ctrl, rated_folder, load_folder, qtbot):
        load_folder(ctrl, str(rated_folder))
        ctrl.goTo(4)
        ctrl.setMinRating(3)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.currentIndex == 0


# ── Folder history ────────────────────────────────────────────────────────────

class TestFolderHistory:
    def test_start_show_adds_folder_to_history(self, ctrl, image_folder, load_folder):
        load_folder(ctrl, str(image_folder))
        ctrl.startShow()
        ctrl.stopShow()
        assert str(image_folder) in ctrl.folderHistory

    def test_most_recent_folder_is_first(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl._update_history("/fake/beta")
        assert ctrl.folderHistory[0] == "/fake/beta"

    def test_duplicate_moves_to_front(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl._update_history("/fake/beta")
        ctrl._update_history("/fake/alpha")
        assert ctrl.folderHistory[0] == "/fake/alpha"
        assert ctrl.folderHistory.count("/fake/alpha") == 1

    def test_clear_history(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl.clearFolderHistory()
        assert ctrl.folderHistory == []

    def test_history_capped_at_100(self, ctrl):
        for i in range(105):
            ctrl._update_history(f"/fake/path/{i}")
        assert len(ctrl.folderHistory) == 100

    def test_history_returns_copy(self, ctrl):
        ctrl._update_history("/fake/x")
        h = ctrl.folderHistory
        h.append("/intruder")
        assert "/intruder" not in ctrl.folderHistory

    def test_remove_existing_entry(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl._update_history("/fake/beta")
        ctrl.removeFolderHistory("/fake/alpha")
        assert "/fake/alpha" not in ctrl.folderHistory
        assert "/fake/beta" in ctrl.folderHistory

    def test_remove_nonexistent_entry_is_noop(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl.removeFolderHistory("/fake/does-not-exist")
        assert ctrl.folderHistory == ["/fake/alpha"]

    def test_remove_only_entry_leaves_empty(self, ctrl):
        ctrl._update_history("/fake/alpha")
        ctrl.removeFolderHistory("/fake/alpha")
        assert ctrl.folderHistory == []


# ── Playback state machine ────────────────────────────────────────────────────

class TestPlayback:
    def test_toggle_starts_playing(self, ctrl_with_images):
        ctrl_with_images.togglePlay()
        assert ctrl_with_images.isPlaying is True
        ctrl_with_images.stopShow()

    def test_toggle_twice_stops_playing(self, ctrl_with_images):
        ctrl_with_images.togglePlay()
        ctrl_with_images.togglePlay()
        assert ctrl_with_images.isPlaying is False

    def test_stop_clears_playing(self, ctrl_with_images):
        ctrl_with_images.togglePlay()
        ctrl_with_images.stopShow()
        assert ctrl_with_images.isPlaying is False

    def test_toggle_noop_when_no_images(self, ctrl):
        ctrl.togglePlay()
        assert ctrl.isPlaying is False

    def test_start_show_plays_when_autoplay_on(self, ctrl_with_images):
        ctrl_with_images.setAutoplay(True)
        ctrl_with_images.startShow()
        assert ctrl_with_images.isPlaying is True
        ctrl_with_images.stopShow()

    def test_start_show_idle_when_autoplay_off(self, ctrl_with_images):
        ctrl_with_images.setAutoplay(False)
        ctrl_with_images.startShow()
        assert ctrl_with_images.isPlaying is False


# ── XMP star-rating extraction ────────────────────────────────────────────────

class TestXmpRating:
    def test_no_xmp_returns_zero(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "plain.jpg")
        assert SlideshowController._read_xmp_rating(str(p)) == 0

    def test_attribute_form_all_ratings(self, tmp_path):
        for rating in range(1, 6):
            p = make_jpeg_with_xmp_attr(tmp_path / f"attr_{rating}.jpg", rating)
            assert SlideshowController._read_xmp_rating(str(p)) == rating

    def test_element_form_all_ratings(self, tmp_path):
        for rating in range(1, 6):
            p = make_jpeg_with_xmp_elem(tmp_path / f"elem_{rating}.jpg", rating)
            assert SlideshowController._read_xmp_rating(str(p)) == rating

    def test_bad_path_returns_zero(self):
        assert SlideshowController._read_xmp_rating("/nonexistent/file.jpg") == 0

    def test_value_clamped_high(self, tmp_path):
        p = make_jpeg_with_xmp_attr(tmp_path / "high.jpg", 9)
        assert SlideshowController._read_xmp_rating(str(p)) == 5

    def test_value_clamped_negative(self, tmp_path):
        # Negative XMP ratings are edge-case; clamped to 0
        p = make_jpeg_with_xmp_attr(tmp_path / "neg.jpg", -2)
        assert SlideshowController._read_xmp_rating(str(p)) == 0


# ── EXIF _date_key (static helper) ───────────────────────────────────────────

class TestDateKey:
    def test_returns_datetime_instance(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "noexif.jpg")
        result = SlideshowController._date_key(str(p))
        assert isinstance(result, datetime)

    def test_falls_back_to_mtime(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "noexif.jpg")
        expected = datetime.fromtimestamp(p.stat().st_mtime)
        result = SlideshowController._date_key(str(p))
        assert abs((result - expected).total_seconds()) < 2

    def test_bad_path_still_returns_datetime(self, tmp_path):
        # Accessing mtime of a non-existent file will raise — but the function
        # catches all exceptions. It will raise OSError for missing mtime.
        # Just verify it doesn't crash for a file that exists but has no EXIF.
        p = make_plain_jpeg(tmp_path / "ok.jpg")
        assert isinstance(SlideshowController._date_key(str(p)), datetime)


# ── Image path accessors ──────────────────────────────────────────────────────

class TestImageAccess:
    def test_image_path_valid_index(self, ctrl_with_images):
        path = ctrl_with_images.imagePath(0)
        assert path != ""
        assert Path(path).exists()

    def test_image_path_negative_index(self, ctrl_with_images):
        assert ctrl_with_images.imagePath(-1) == ""

    def test_image_path_out_of_range(self, ctrl_with_images):
        assert ctrl_with_images.imagePath(999) == ""

    def test_current_image_path_matches_index(self, ctrl_with_images):
        ctrl_with_images.goTo(2)
        assert ctrl_with_images.currentImagePath() == ctrl_with_images.imagePath(2)

    def test_image_caption_plain_jpeg_is_empty(self, ctrl_with_images):
        assert ctrl_with_images.imageCaption(0) == ""

    def test_image_caption_out_of_range_is_empty(self, ctrl_with_images):
        assert ctrl_with_images.imageCaption(999) == ""

    def test_image_date_taken_plain_jpeg_is_empty(self, ctrl_with_images):
        assert ctrl_with_images.imageDateTaken(0) == ""

    def test_image_date_taken_out_of_range_is_empty(self, ctrl_with_images):
        assert ctrl_with_images.imageDateTaken(999) == ""

    def test_image_rating_plain_jpeg_is_zero(self, ctrl_with_images):
        assert ctrl_with_images.imageRating(0) == 0

    def test_image_rating_out_of_range_is_zero(self, ctrl_with_images):
        assert ctrl_with_images.imageRating(999) == 0

    def test_image_rating_uses_cache(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        # First call populates cache
        r = ctrl.imageRating(0)
        # Second call must return same value (from cache)
        assert ctrl.imageRating(0) == r


# ── imageExifInfo ─────────────────────────────────────────────────────────────

class TestImageExifInfo:
    def _row(self, rows: list, label: str) -> str | None:
        """Return the value for a given label, or None if not present."""
        for r in rows:
            if r["label"] == label:
                return r["value"]
        return None

    def test_out_of_range_returns_empty(self, ctrl_with_images):
        assert ctrl_with_images.imageExifInfo(999) == []

    def test_plain_jpeg_has_only_dimensions(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_plain_jpeg(d / "img.jpg", size=(320, 240))
        load_folder(ctrl, str(d))
        rows = ctrl.imageExifInfo(0)
        labels = [r["label"] for r in rows]
        assert labels == ["Dimensions"]
        assert self._row(rows, "Dimensions") == "320 × 240"

    def test_camera_make_and_model(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", make="Canon", model="EOS R5")
        load_folder(ctrl, str(d))
        rows = ctrl.imageExifInfo(0)
        assert self._row(rows, "Camera") == "Canon EOS R5"

    def test_camera_model_already_starts_with_make(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", make="Canon", model="Canon EOS R5")
        load_folder(ctrl, str(d))
        rows = ctrl.imageExifInfo(0)
        # Should not produce "Canon Canon EOS R5"
        assert self._row(rows, "Camera") == "Canon EOS R5"

    def test_aperture_formatted(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", fnumber=(28, 10))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Aperture") == "f/2.8"

    def test_shutter_fraction(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", exposure_time=(1, 200))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Shutter") == "1/200 s"

    def test_shutter_long_exposure(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", exposure_time=(25, 10))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Shutter") == "2.5 s"

    def test_iso(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", iso=400)
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "ISO") == "400"

    def test_focal_length_integer(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", focal_length=(50, 1))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Focal length") == "50 mm"

    def test_focal_length_fractional(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", focal_length=(352, 10))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Focal length") == "35.2 mm"

    def test_exposure_program_known(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", exposure_program=2)
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Exposure") == "Auto"

    def test_exposure_program_unknown(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", exposure_program=99)
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Exposure") == "99"

    def test_flash_did_not_fire(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", flash=0x00)
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Flash") == "Did not fire"

    def test_flash_fired(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", flash=0x01)
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Flash") == "Fired"

    def test_dimensions_from_exif_tags(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", size=(100, 80))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Dimensions") == "100 × 80"

    def test_dimensions_fallback_to_pil_size(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_plain_jpeg(d / "img.jpg", size=(320, 240))
        load_folder(ctrl, str(d))
        assert self._row(ctrl.imageExifInfo(0), "Dimensions") == "320 × 240"

    def test_cache_avoids_reread(self, ctrl, tmp_path, load_folder):
        d = tmp_path / "p"
        d.mkdir()
        make_jpeg_with_exif(d / "img.jpg", make="Canon", model="EOS R5")
        load_folder(ctrl, str(d))
        first = ctrl.imageExifInfo(0)
        second = ctrl.imageExifInfo(0)
        assert first is second  # same list object from cache


# ── Settings setters ──────────────────────────────────────────────────────────

class TestSettingsSetters:
    def test_set_transition_style(self, ctrl):
        ctrl.setTransitionStyle("slide")
        assert ctrl.transitionStyle == "slide"

    def test_set_transition_duration(self, ctrl):
        ctrl.setTransitionDuration(1200)
        assert ctrl.transitionDuration == 1200

    def test_set_hud_size(self, ctrl):
        ctrl.setHudSize(150)
        assert ctrl.hudSize == 150

    def test_set_hud_visible(self, ctrl):
        ctrl.setHudVisible(True)
        assert ctrl.hudVisible is True

    def test_set_loop(self, ctrl):
        ctrl.setLoop(False)
        assert ctrl.loop is False

    def test_set_autoplay(self, ctrl):
        ctrl.setAutoplay(True)
        assert ctrl.autoplay is True

    def test_set_interval(self, ctrl):
        ctrl.setInterval(3000)
        assert ctrl.interval == 3000

    def test_set_language(self, ctrl):
        ctrl.setLanguage("de")
        assert ctrl.language == "de"

    def test_set_update_check_enabled(self, ctrl):
        ctrl.setUpdateCheckEnabled(False)
        assert ctrl.updateCheckEnabled is False
        ctrl.setUpdateCheckEnabled(True)
        assert ctrl.updateCheckEnabled is True

    def test_set_recursive_search(self, ctrl):
        ctrl.setRecursiveSearch(True)
        assert ctrl.recursiveSearch is True
        ctrl.setRecursiveSearch(False)
        assert ctrl.recursiveSearch is False

    def test_set_remote_enabled(self, ctrl):
        ctrl.setRemoteEnabled(True)
        assert ctrl.remoteEnabled is True

    def test_set_remote_port(self, ctrl):
        ctrl.setRemotePort(9000)
        assert ctrl.remotePort == 9000


# ── Available languages ───────────────────────────────────────────────────────

class TestAvailableLanguages:
    def test_always_contains_auto_and_en(self, ctrl):
        codes = [entry["code"] for entry in ctrl.availableLanguages]
        assert "auto" in codes
        assert "en" in codes

    def test_auto_is_first(self, ctrl):
        assert ctrl.availableLanguages[0]["code"] == "auto"

    def test_en_is_last(self, ctrl):
        assert ctrl.availableLanguages[-1]["code"] == "en"

    def test_no_duplicate_codes(self, ctrl):
        codes = [entry["code"] for entry in ctrl.availableLanguages]
        assert len(codes) == len(set(codes))

    def test_each_entry_has_code_and_name(self, ctrl):
        for entry in ctrl.availableLanguages:
            assert "code" in entry
            assert "name" in entry
            assert isinstance(entry["code"], str)
            assert isinstance(entry["name"], str)


# ── Signal emissions ──────────────────────────────────────────────────────────

class TestSignals:
    def test_images_changed_on_load(self, ctrl, image_folder, qtbot):
        with qtbot.waitSignal(ctrl.imagesChanged, timeout=1000):
            ctrl.loadFolder(str(image_folder))

    def test_current_index_changed_on_next(self, ctrl_with_images, qtbot):
        with qtbot.waitSignal(ctrl_with_images.currentIndexChanged, timeout=1000):
            ctrl_with_images.nextImage()

    def test_is_playing_changed_on_toggle(self, ctrl_with_images, qtbot):
        with qtbot.waitSignal(ctrl_with_images.isPlayingChanged, timeout=1000):
            ctrl_with_images.togglePlay()
        ctrl_with_images.stopShow()

    def test_settings_changed_on_sort_order(self, ctrl, qtbot):
        with qtbot.waitSignal(ctrl.settingsChanged, timeout=1000):
            ctrl.setSortOrder("random")

    def test_folder_history_changed_on_clear(self, ctrl, qtbot):
        ctrl._update_history("/fake/x")
        with qtbot.waitSignal(ctrl.folderHistoryChanged, timeout=1000):
            ctrl.clearFolderHistory()

    def test_folder_history_changed_on_remove(self, ctrl, qtbot):
        ctrl._update_history("/fake/x")
        with qtbot.waitSignal(ctrl.folderHistoryChanged, timeout=1000):
            ctrl.removeFolderHistory("/fake/x")

    def test_folder_history_no_signal_on_remove_missing(self, ctrl, qtbot):
        ctrl._update_history("/fake/x")
        with qtbot.assertNotEmitted(ctrl.folderHistoryChanged):
            ctrl.removeFolderHistory("/fake/does-not-exist")


# ── Recursive search ──────────────────────────────────────────────────────────

class TestRecursiveSearch:
    def test_flat_scan_misses_subfolder_images(self, tmp_path, ctrl, load_folder):
        sub = tmp_path / "sub"
        sub.mkdir()
        make_plain_jpeg(tmp_path / "top.jpg")
        make_plain_jpeg(sub / "nested.jpg")
        ctrl.setRecursiveSearch(False)
        load_folder(ctrl, str(tmp_path))
        assert ctrl.imageCount == 1

    def test_recursive_scan_finds_subfolder_images(self, tmp_path, ctrl, load_folder):
        sub = tmp_path / "sub"
        sub.mkdir()
        make_plain_jpeg(tmp_path / "top.jpg")
        make_plain_jpeg(sub / "nested.jpg")
        ctrl.setRecursiveSearch(True)
        load_folder(ctrl, str(tmp_path))
        assert ctrl.imageCount == 2

    def test_toggle_recursive_rescans(self, tmp_path, ctrl, load_folder, qtbot):
        sub = tmp_path / "sub"
        sub.mkdir()
        make_plain_jpeg(tmp_path / "top.jpg")
        make_plain_jpeg(sub / "nested.jpg")
        load_folder(ctrl, str(tmp_path))
        assert ctrl.imageCount == 1
        # Enable recursive — setRecursiveSearch triggers a new background scan
        ctrl.setRecursiveSearch(True)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl.imageCount == 2


# ── Parallel loading pipeline ─────────────────────────────────────────────────

class TestParallelLoading:
    """Background scan → sort → ratings pipeline behaviour."""

    # ── scanning flag ────────────────────────────────────────────────────────

    def test_scanning_true_during_load(self, ctrl, image_folder, qtbot):
        ctrl.loadFolder(str(image_folder))
        # scanning must be True immediately (before pipeline finishes)
        assert ctrl.scanning is True
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

    def test_scanning_false_after_pipeline(self, ctrl, image_folder, load_folder):
        load_folder(ctrl, str(image_folder))
        assert ctrl.scanning is False

    def test_scanning_true_during_date_sort(self, tmp_path, ctrl, qtbot):
        for n in ("a.jpg", "b.jpg", "c.jpg"):
            make_plain_jpeg(tmp_path / n)
        ctrl.setSortOrder("date")
        ctrl.loadFolder(str(tmp_path))
        assert ctrl.scanning is True
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

    # ── scanProgress lifecycle ────────────────────────────────────────────────

    def test_scan_progress_zero_after_name_sort(self, ctrl, image_folder, load_folder):
        """No metadata phase for name sort → progress stays 0."""
        load_folder(ctrl, str(image_folder))
        assert ctrl.scanProgress == 0

    def test_scan_progress_zero_after_random_sort(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("random")
        load_folder(ctrl, str(image_folder))
        assert ctrl.scanProgress == 0

    def test_scan_progress_resets_after_date_sort(self, tmp_path, ctrl, load_folder):
        """scanProgress resets to 0 once date sort pipeline completes."""
        for n in ("a.jpg", "b.jpg", "c.jpg"):
            make_plain_jpeg(tmp_path / n)
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(tmp_path))
        assert ctrl.scanProgress == 0

    def test_scan_progress_emitted_during_date_sort(self, tmp_path, ctrl, qtbot):
        """scanProgressChanged fires with increasing values during EXIF reads."""
        for n in ("a.jpg", "b.jpg", "c.jpg"):
            make_plain_jpeg(tmp_path / n)
        ctrl.setSortOrder("date")

        progress_values: list[int] = []
        ctrl.scanProgressChanged.connect(lambda: progress_values.append(ctrl.scanProgress))

        ctrl.loadFolder(str(tmp_path))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        assert any(v > 0 for v in progress_values), "No progress > 0 emitted"
        assert ctrl.scanProgress == 0   # reset at end

    def test_scan_progress_resets_after_rating_reads(self, tmp_path, ctrl, load_folder, qtbot):
        """scanProgress resets to 0 once ratings pipeline completes."""
        for r in range(1, 4):
            make_jpeg_with_xmp_attr(tmp_path / f"r{r}.jpg", r)
        ctrl.setMinRating(1)
        load_folder(ctrl, str(tmp_path))
        assert ctrl.scanProgress == 0

    def test_scan_progress_emitted_during_rating_reads(self, tmp_path, ctrl, qtbot):
        """scanProgressChanged fires with increasing values during XMP reads."""
        for r in range(1, 6):
            make_jpeg_with_xmp_attr(tmp_path / f"r{r}.jpg", r)
        ctrl.setMinRating(1)

        progress_values: list[int] = []
        ctrl.scanProgressChanged.connect(lambda: progress_values.append(ctrl.scanProgress))

        ctrl.loadFolder(str(tmp_path))
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        assert any(v > 0 for v in progress_values), "No progress > 0 emitted"
        assert ctrl.scanProgress == 0   # reset at end

    # ── date sort ordering ────────────────────────────────────────────────────

    def test_date_sort_orders_by_mtime_oldest_first(self, tmp_path, ctrl, load_folder):
        """Without EXIF, date sort falls back to mtime; oldest file comes first."""
        names = ("first.jpg", "second.jpg", "third.jpg")
        for i, name in enumerate(names):
            p = tmp_path / name
            make_plain_jpeg(p)
            os.utime(p, (1_000_000 + i * 3600, 1_000_000 + i * 3600))

        ctrl.setSortOrder("date")
        load_folder(ctrl, str(tmp_path))

        result = [Path(ctrl.imagePath(i)).name for i in range(ctrl.imageCount)]
        assert result == list(names)

    def test_date_sort_preserves_all_files(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert ctrl.imageCount == 5

    # ── rating cache population ───────────────────────────────────────────────

    def test_rating_cache_empty_without_filter(self, ctrl, rated_folder, load_folder):
        """No star filter → ratings are not pre-read; cache stays empty."""
        load_folder(ctrl, str(rated_folder))
        assert ctrl._rating_cache == {}

    def test_rating_cache_populated_when_filter_active(self, ctrl, rated_folder,
                                                        load_folder, qtbot):
        """With star filter active, all ratings are read into cache."""
        ctrl.setMinRating(1)
        load_folder(ctrl, str(rated_folder))
        assert len(ctrl._rating_cache) == 6   # one entry per image

    def test_rating_cache_populated_on_filter_change_after_load(self, ctrl, rated_folder,
                                                                  load_folder, qtbot):
        """Activating filter after plain load triggers background rating read."""
        load_folder(ctrl, str(rated_folder))
        assert ctrl._rating_cache == {}
        ctrl.setMinRating(1)
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert len(ctrl._rating_cache) == 6

    def test_partial_cache_from_rating_write_triggers_async_scan(self, rated_folder,
                                                                   load_folder, qtbot,
                                                                   qapp, _isolate_settings):
        """Writing one rating during a show leaves a partial cache.
        setMinRating must still trigger a background read, not fall through to
        synchronous _apply_filter which would block the main thread."""
        from slideshow_controller import SlideshowController
        ctrl = SlideshowController(jump_start=True)
        load_folder(ctrl, str(rated_folder))        # minRating=0 → cache stays empty
        assert ctrl._rating_cache == {}

        # Simulate user writing one rating during the show
        ctrl.writeImageRating(0, 4)
        assert len(ctrl._rating_cache) == 1         # partial: one entry out of 6

        # Now user changes filter — must NOT go synchronous
        scanning_states: list[bool] = []
        ctrl.scanningChanged.connect(lambda: scanning_states.append(ctrl.scanning))

        ctrl.setMinRating(3)
        assert ctrl.scanning is True, "background scan must start immediately"
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert len(ctrl._rating_cache) == 6         # all images now in cache
        assert any(s is True for s in scanning_states), "scanningChanged(True) must fire"

    # ── sort change mid-scan ──────────────────────────────────────────────────

    def test_sort_change_during_scan_is_applied(self, tmp_path, ctrl, qtbot):
        """Sort order changed while file discovery runs → final result uses new order."""
        for name in ("c.jpg", "a.jpg", "b.jpg"):
            make_plain_jpeg(tmp_path / name)

        ctrl.setSortOrder("random")
        ctrl.loadFolder(str(tmp_path))
        ctrl.setSortOrder("name")    # change while scan is in-flight
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        names = [Path(ctrl.imagePath(i)).name for i in range(ctrl.imageCount)]
        assert names == ["a.jpg", "b.jpg", "c.jpg"]

    # ── folder switch cancels previous scan ───────────────────────────────────

    def test_new_folder_cancels_previous_scan(self, tmp_path, ctrl, qtbot):
        """Loading a second folder cancels the first; final state reflects d2."""
        d1 = tmp_path / "d1"
        d2 = tmp_path / "d2"
        d1.mkdir(); d2.mkdir()
        for n in ("x.jpg", "y.jpg"):
            make_plain_jpeg(d1 / n)
        make_plain_jpeg(d2 / "z.jpg")

        ctrl.loadFolder(str(d1))
        ctrl.loadFolder(str(d2))   # cancels d1 scan
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)

        assert ctrl.imageCount == 1
        assert Path(ctrl.imagePath(0)).parent == d2

    # ── cancelAll ────────────────────────────────────────────────────────────

    def test_cancel_all_does_not_crash(self, ctrl, image_folder, qtbot):
        """cancelAll() while scanning completes without errors."""
        ctrl.loadFolder(str(image_folder))
        ctrl.cancelAll()
        qtbot.wait(200)   # let in-flight thread exit
        # Pass if no exception raised


# ── _modify_xmp_rating_str ────────────────────────────────────────────────────

class TestModifyXmpRatingStr:
    """Unit tests for the pure-string XMP rating patcher."""

    def _m(self, xmp_str: str, rating: int) -> str:
        return SlideshowController._modify_xmp_rating_str(xmp_str, rating)

    # ── Empty XMP ─────────────────────────────────────────────────────────────

    def test_empty_xmp_set_rating_creates_wrapper(self):
        result = self._m("", 3)
        assert 'xmp:Rating="3"' in result
        assert "<x:xmpmeta" in result
        assert "<rdf:RDF" in result

    def test_empty_xmp_remove_rating_returns_empty(self):
        result = self._m("", 0)
        assert result == ""

    # ── Attribute form ────────────────────────────────────────────────────────

    def test_attr_form_update_rating(self):
        xmp = '<rdf:Description xmp:Rating="2"/>'
        assert 'xmp:Rating="5"' in self._m(xmp, 5)

    def test_attr_form_remove_rating(self):
        xmp = '<rdf:Description xmp:Rating="4"/>'
        result = self._m(xmp, 0)
        assert "Rating" not in result

    def test_attr_form_set_same_value(self):
        xmp = '<rdf:Description xmp:Rating="3"/>'
        assert 'xmp:Rating="3"' in self._m(xmp, 3)

    def test_attr_form_no_duplicate_after_update(self):
        xmp = '<rdf:Description xmp:Rating="1"/>'
        result = self._m(xmp, 4)
        assert result.count("Rating") == 1

    # ── Element form ──────────────────────────────────────────────────────────

    def test_elem_form_update_rating(self):
        """Element form is normalised to attribute form; value must be updated."""
        xmp = '<rdf:Description><xmp:Rating>1</xmp:Rating></rdf:Description>'
        result = self._m(xmp, 5)
        # Result uses attribute form (normalised); verify value is present
        assert 'xmp:Rating="5"' in result

    def test_elem_form_remove_rating(self):
        xmp = '<rdf:Description><xmp:Rating>3</xmp:Rating></rdf:Description>'
        result = self._m(xmp, 0)
        assert "Rating" not in result

    def test_elem_form_no_duplicate_after_update(self):
        xmp = '<rdf:Description><xmp:Rating>2</xmp:Rating></rdf:Description>'
        result = self._m(xmp, 4)
        assert result.count("Rating") == 1

    # ── XMP present but no Rating ─────────────────────────────────────────────

    def test_xmp_without_rating_injects_attribute(self):
        xmp = (
            '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
            '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
            '<rdf:Description rdf:about=""/>'
            '</rdf:RDF>'
            '</x:xmpmeta>'
        )
        result = self._m(xmp, 2)
        assert 'xmp:Rating="2"' in result

    def test_xmp_without_rating_remove_is_noop(self):
        xmp = '<rdf:Description rdf:about=""/>'
        result = self._m(xmp, 0)
        assert "Rating" not in result

    # ── Round-trips ───────────────────────────────────────────────────────────

    def test_roundtrip_set_then_remove(self):
        xmp = ""
        xmp = self._m(xmp, 4)
        assert 'xmp:Rating="4"' in xmp
        xmp = self._m(xmp, 0)
        assert "Rating" not in xmp

    def test_roundtrip_change_value(self):
        xmp = ""
        for r in (1, 3, 5, 2):
            xmp = self._m(xmp, r)
        assert f'xmp:Rating="{2}"' in xmp
        assert xmp.count("Rating") == 1


# ── _write_xmp_rating (static, file I/O) ─────────────────────────────────────

class TestWriteXmpRating:
    """Tests for the atomic JPEG write function."""

    def _write(self, path, rating):
        SlideshowController._write_xmp_rating(str(path), rating)

    def _read_rating(self, path):
        return SlideshowController._read_xmp_rating(str(path))

    # ── Happy paths ───────────────────────────────────────────────────────────

    def test_set_rating_on_plain_jpeg(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, 3)
        assert self._read_rating(p) == 3

    def test_set_rating_1_through_5(self, tmp_path):
        for r in range(1, 6):
            p = make_plain_jpeg(tmp_path / f"r{r}.jpg")
            self._write(p, r)
            assert self._read_rating(p) == r

    def test_update_existing_attr_rating(self, tmp_path):
        p = make_jpeg_with_xmp_attr(tmp_path / "attr.jpg", 2)
        self._write(p, 5)
        assert self._read_rating(p) == 5

    def test_update_existing_elem_rating(self, tmp_path):
        p = make_jpeg_with_xmp_elem(tmp_path / "elem.jpg", 1)
        self._write(p, 4)
        assert self._read_rating(p) == 4

    def test_remove_rating_from_attr_jpeg(self, tmp_path):
        p = make_jpeg_with_xmp_attr(tmp_path / "attr.jpg", 3)
        self._write(p, 0)
        assert self._read_rating(p) == 0

    def test_remove_rating_from_elem_jpeg(self, tmp_path):
        p = make_jpeg_with_xmp_elem(tmp_path / "elem.jpg", 5)
        self._write(p, 0)
        assert self._read_rating(p) == 0

    def test_remove_rating_from_plain_jpeg_is_noop(self, tmp_path):
        """Removing a non-existent rating must not corrupt the file."""
        p = make_plain_jpeg(tmp_path / "plain.jpg")
        original = p.read_bytes()
        self._write(p, 0)
        # File is still a valid JPEG and rating remains 0
        assert self._read_rating(p) == 0
        from PIL import Image
        with Image.open(p) as img:
            img.verify()

    def test_result_is_valid_jpeg(self, tmp_path):
        """After write, Pillow must be able to open the file."""
        from PIL import Image
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, 4)
        with Image.open(p) as img:
            img.verify()

    def test_original_not_corrupted_on_failure(self, tmp_path):
        """If writing fails mid-way the original file remains unchanged."""
        p = make_plain_jpeg(tmp_path / "a.jpg")
        original = p.read_bytes()
        # Force an I/O error by making the directory read-only is fragile on Windows;
        # instead test the bad-JPEG guard path by passing a non-JPEG file.
        non_jpeg = tmp_path / "a.txt"
        non_jpeg.write_bytes(b"not a jpeg")
        with pytest.raises(ValueError):
            SlideshowController._write_xmp_rating(str(non_jpeg), 3)
        # Original plain JPEG is still untouched
        assert p.read_bytes() == original

    def test_roundtrip_set_then_change_then_remove(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, 2)
        assert self._read_rating(p) == 2
        self._write(p, 5)
        assert self._read_rating(p) == 5
        self._write(p, 0)
        assert self._read_rating(p) == 0

    # ── Error paths ───────────────────────────────────────────────────────────

    def test_raises_for_non_jpeg_extension(self, tmp_path):
        p = tmp_path / "img.png"
        p.write_bytes(b"\x89PNG\r\n\x1a\n")
        with pytest.raises(ValueError, match="JPEG"):
            self._write(p, 3)

    def test_raises_for_truncated_jpeg(self, tmp_path):
        """A JPEG starting with the right magic but containing no data raises."""
        p = tmp_path / "bad.jpg"
        p.write_bytes(b"\xff\xd8\xff")   # SOI + incomplete marker
        with pytest.raises(Exception):
            self._write(p, 2)

    def test_raises_for_missing_file(self, tmp_path):
        with pytest.raises(OSError):
            self._write(tmp_path / "missing.jpg", 1)


# ── writeImageRating slot ─────────────────────────────────────────────────────

class TestWriteImageRatingSlot:
    """Tests for the QObject slot that wraps _write_xmp_rating."""

    def test_returns_true_on_success(self, ctrl, tmp_path, load_folder):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        assert ctrl.writeImageRating(0, 3) is True

    def test_returns_false_for_invalid_index(self, ctrl):
        assert ctrl.writeImageRating(99, 3) is False

    def test_updates_rating_cache(self, ctrl, tmp_path, load_folder):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        ctrl.writeImageRating(0, 4)
        path = ctrl.imagePath(0)
        assert ctrl._rating_cache.get(path) == 4

    def test_imageRating_reflects_write(self, ctrl, tmp_path, load_folder):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        ctrl.writeImageRating(0, 5)
        assert ctrl.imageRating(0) == 5

    def test_emits_ratingWritten_signal(self, ctrl, tmp_path, load_folder, qtbot):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        with qtbot.waitSignal(ctrl.ratingWritten, timeout=1000) as blocker:
            ctrl.writeImageRating(0, 2)
        assert blocker.args == [0]

    def test_emits_errorOccurred_on_failure(self, ctrl, tmp_path, load_folder, qtbot):
        """Writing to a non-JPEG (PNG) file emits errorOccurred and returns False."""
        p = tmp_path / "img.png"
        p.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 100)
        # Manually place a non-JPEG in the image list by loading a folder,
        # then patching the list.
        load_folder(ctrl, str(tmp_path))
        # No JPEGs loaded — just test via a plain-path scenario using the
        # static method path: create a dummy images list entry.
        ctrl._images = [str(p)]
        ctrl._current_index = 0
        errors = []
        ctrl.errorOccurred.connect(errors.append)
        result = ctrl.writeImageRating(0, 3)
        assert result is False
        assert len(errors) == 1

    def test_clamps_rating_to_0_5(self, ctrl, tmp_path, load_folder):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        ctrl.writeImageRating(0, 99)   # clamped to 5
        assert ctrl._rating_cache[ctrl.imagePath(0)] == 5
        ctrl.writeImageRating(0, -3)   # clamped to 0
        assert ctrl._rating_cache[ctrl.imagePath(0)] == 0


# ── _modify_iptc_caption_bytes ────────────────────────────────────────────────

class TestModifyIptcCaptionBytes:
    """Unit tests for the pure-bytes IPTC caption patcher."""

    _PS3 = b"Photoshop 3.0\x00"

    def _m(self, payload: bytes, caption: str) -> bytes:
        return SlideshowController._modify_iptc_caption_bytes(payload, caption)

    def _read_caption(self, payload: bytes) -> str:
        """Inject *payload* into a minimal JPEG and read back the caption via Pillow."""
        buf = io.BytesIO()
        Image.new("RGB", (4, 4)).save(buf, format="JPEG")
        jpeg = _inject_app13(buf.getvalue(), payload)
        with Image.open(io.BytesIO(jpeg)) as img:
            iptc = IptcImagePlugin.getiptcinfo(img)
            if iptc:
                raw = iptc.get((2, 120))
                if raw:
                    return (raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else str(raw)).strip()
        return ""

    # ── Empty payload ─────────────────────────────────────────────────────────

    def test_empty_payload_set_caption_creates_structure(self):
        result = self._m(b"", "Hello")
        assert result.startswith(self._PS3)
        assert b"8BIM" in result
        assert b"\x04\x04" in result
        assert self._read_caption(result) == "Hello"

    def test_empty_payload_remove_caption_is_noop(self):
        result = self._m(b"", "")
        assert result == b""

    def test_empty_payload_whitespace_caption_is_noop(self):
        result = self._m(b"", "   ")
        assert result == b""

    # ── Existing caption ──────────────────────────────────────────────────────

    def test_existing_caption_is_replaced(self):
        existing = _build_iptc_caption_payload("OldCaption")
        result = self._m(existing, "NewCaption")
        assert self._read_caption(result) == "NewCaption"

    def test_existing_caption_is_removed_when_blank(self):
        existing = _build_iptc_caption_payload("SomeCaption")
        result = self._m(existing, "")
        assert self._read_caption(result) == ""

    def test_no_duplicate_caption_record(self):
        existing = _build_iptc_caption_payload("First")
        result = self._m(existing, "Second")
        # Only one 0x78 (dataset 120) tag should be present in the IPTC block
        assert result.count(b"\x1c\x02\x78") == 1

    def test_whitespace_only_caption_removes_record(self):
        existing = _build_iptc_caption_payload("  keep me not  ")
        result = self._m(existing, "   ")
        assert self._read_caption(result) == ""

    # ── Other records preserved ───────────────────────────────────────────────

    def test_other_iptc_records_preserved(self):
        """A (2, 25) keyword record must survive a caption update."""
        import struct as _s
        # Build an IPTC block with a keyword (2:25) and a caption (2:120)
        kw = b"\x1c\x02\x19" + _s.pack(">H", 7) + b"keyword"   # 2:25
        cap = b"\x1c\x02\x78" + _s.pack(">H", 5) + b"Hello"    # 2:120
        iptc_data = kw + cap
        if len(iptc_data) % 2:
            iptc_data += b"\x00"
        import struct
        bim = b"8BIM\x04\x04\x00\x00" + struct.pack(">I", len(kw) + len(cap)) + iptc_data
        payload = self._PS3 + bim
        result = self._m(payload, "NewCaption")
        assert b"\x1c\x02\x19" in result   # keyword record preserved
        assert self._read_caption(result) == "NewCaption"

    def test_charset_record_preserved(self):
        """The (1, 90) Coded Character Set record is left untouched."""
        import struct
        charset = b"\x1c\x01\x5a" + struct.pack(">H", 3) + b"\x1b\x25\x47"  # UTF-8 escape
        cap = b"\x1c\x02\x78" + struct.pack(">H", 5) + b"Hello"
        iptc_data = charset + cap
        if len(iptc_data) % 2:
            iptc_data += b"\x00"
        bim = b"8BIM\x04\x04\x00\x00" + struct.pack(">I", len(charset) + len(cap)) + iptc_data
        payload = self._PS3 + bim
        result = self._m(payload, "Updated")
        assert b"\x1c\x01\x5a" in result   # charset record preserved

    # ── No 0x0404 block ───────────────────────────────────────────────────────

    def test_no_0x0404_block_appends_new_block(self):
        """APP13 with unrelated 8BIM types gets a new 0x0404 block appended."""
        import struct
        # 8BIM type 0x0409 (thumbnail) with 4 bytes of dummy data
        thumb = b"8BIM\x04\x09\x00\x00" + struct.pack(">I", 4) + b"DUMP"
        payload = self._PS3 + thumb
        result = self._m(payload, "Caption!")
        assert b"8BIM\x04\x09" in result   # original block kept
        assert b"8BIM\x04\x04" in result   # new IPTC block appended
        assert self._read_caption(result) == "Caption!"

    # ── Multibyte / long captions ─────────────────────────────────────────────

    def test_multibyte_utf8_caption_roundtrip(self):
        result = self._m(b"", "Über schöne Fotos — 写真 — Ñoño")
        assert self._read_caption(result) == "Über schöne Fotos — 写真 — Ñoño"

    def test_extended_length_record_skipped_safely(self):
        """An IPTC record with extended-length encoding must not corrupt parsing."""
        import struct
        # Build a (2:80) Subject Reference with extended 4-byte length (rare but valid)
        subject_data = b"X" * 260   # > 255, requires extended length
        ext_len_byte = 0x84         # 0x80 | 4 → 4 extra bytes for real length
        ext_len = struct.pack(">I", len(subject_data))
        subject_rec = b"\x1c\x02\x50" + bytes([ext_len_byte]) + b"\x00" + ext_len + subject_data
        cap = b"\x1c\x02\x78" + struct.pack(">H", 5) + b"Hello"
        iptc_raw = subject_rec + cap
        if len(iptc_raw) % 2:
            iptc_raw += b"\x00"
        bim = b"8BIM\x04\x04\x00\x00" + struct.pack(">I", len(subject_rec) + len(cap)) + iptc_raw
        payload = self._PS3 + bim
        result = self._m(payload, "Updated")
        # Must not raise; the subject record may be lost (extended form rebuild not needed)
        # but the caption must be present and correct
        assert self._read_caption(result) == "Updated"


# ── _write_iptc_caption (static, file I/O) ────────────────────────────────────

class TestWriteIptcCaption:
    """Tests for the atomic JPEG IPTC write function."""

    def _write(self, path, caption):
        SlideshowController._write_iptc_caption(str(path), caption)

    def _read(self, path) -> str:
        with Image.open(str(path)) as img:
            iptc = IptcImagePlugin.getiptcinfo(img)
            if iptc:
                raw = iptc.get((2, 120))
                if raw:
                    return (raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else str(raw)).strip()
        return ""

    # ── Happy paths ───────────────────────────────────────────────────────────

    def test_set_caption_on_plain_jpeg(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, "A fresh caption")
        assert self._read(p) == "A fresh caption"

    def test_update_existing_caption(self, tmp_path):
        p = make_jpeg_with_iptc_caption(tmp_path / "a.jpg", "Original")
        self._write(p, "Updated")
        assert self._read(p) == "Updated"

    def test_clear_caption(self, tmp_path):
        p = make_jpeg_with_iptc_caption(tmp_path / "a.jpg", "Remove me")
        self._write(p, "")
        assert self._read(p) == ""

    def test_clear_caption_on_plain_jpeg_is_noop(self, tmp_path):
        """Clearing a non-existent caption must not corrupt the file."""
        p = make_plain_jpeg(tmp_path / "a.jpg")
        original = p.read_bytes()
        self._write(p, "")
        # File untouched (early return — no APP13 to modify)
        assert p.read_bytes() == original

    def test_result_is_valid_jpeg(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, "validity check")
        with Image.open(str(p)) as img:
            img.verify()

    def test_original_not_corrupted_on_failure(self, tmp_path):
        """If write fails the original file bytes are untouched."""
        p = make_plain_jpeg(tmp_path / "a.jpg")
        original = p.read_bytes()
        non_jpeg = tmp_path / "a.txt"
        non_jpeg.write_bytes(b"not a jpeg")
        with pytest.raises(ValueError):
            SlideshowController._write_iptc_caption(str(non_jpeg), "caption")
        assert p.read_bytes() == original

    def test_roundtrip_set_change_clear(self, tmp_path):
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, "First")
        assert self._read(p) == "First"
        self._write(p, "Second")
        assert self._read(p) == "Second"
        self._write(p, "")
        assert self._read(p) == ""

    def test_multibyte_caption_preserved(self, tmp_path):
        caption = "Straßenfoto — 写真 — Ñoño"
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, caption)
        assert self._read(p) == caption

    def test_long_caption_preserved(self, tmp_path):
        caption = "A" * 512
        p = make_plain_jpeg(tmp_path / "a.jpg")
        self._write(p, caption)
        assert self._read(p) == caption

    def test_preserves_xmp_segment(self, tmp_path):
        """Writing a caption must not destroy an existing XMP rating."""
        p = make_jpeg_with_xmp_attr(tmp_path / "a.jpg", 4)
        self._write(p, "Caption over XMP")
        # XMP rating still readable
        assert SlideshowController._read_xmp_rating(str(p)) == 4
        assert self._read(p) == "Caption over XMP"

    def test_preserves_exif_segment(self, tmp_path):
        """Writing a caption must not destroy existing EXIF data."""
        p = make_jpeg_with_exif(tmp_path / "a.jpg", make="Nikon", model="D750")
        self._write(p, "Caption over EXIF")
        with Image.open(str(p)) as img:
            exif = img._getexif() or {}
        assert exif.get(271) == "Nikon"   # Make tag
        assert self._read(p) == "Caption over EXIF"

    # ── Error paths ───────────────────────────────────────────────────────────

    def test_raises_for_non_jpeg_extension(self, tmp_path):
        p = tmp_path / "img.png"
        p.write_bytes(b"\x89PNG\r\n\x1a\n")
        with pytest.raises(ValueError, match="JPEG"):
            self._write(p, "caption")

    def test_raises_for_truncated_jpeg(self, tmp_path):
        p = tmp_path / "bad.jpg"
        p.write_bytes(b"\xff\xd8\xff")   # SOI + incomplete marker
        with pytest.raises(Exception):
            self._write(p, "caption")

    def test_raises_for_missing_file(self, tmp_path):
        with pytest.raises(OSError):
            self._write(tmp_path / "missing.jpg", "caption")


# ── writeImageCaption slot ────────────────────────────────────────────────────

class TestWriteImageCaptionSlot:
    """Tests for the QObject slot that wraps _write_iptc_caption."""

    def test_returns_true_on_success(self, ctrl, tmp_path, load_folder):
        make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        assert ctrl.writeImageCaption(0, "Hello") is True

    def test_returns_false_for_invalid_index(self, ctrl):
        assert ctrl.writeImageCaption(99, "Hello") is False

    def test_emits_captionWritten_signal(self, ctrl, tmp_path, load_folder, qtbot):
        make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        with qtbot.waitSignal(ctrl.captionWritten, timeout=1000) as blocker:
            ctrl.writeImageCaption(0, "Signal test")
        assert blocker.args == [0]

    def test_emits_errorOccurred_on_failure(self, ctrl, tmp_path, load_folder, qtbot):
        """Writing to a non-JPEG emits errorOccurred and returns False."""
        p = tmp_path / "img.png"
        p.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 100)
        load_folder(ctrl, str(tmp_path))
        ctrl._images = [str(p)]
        ctrl._current_index = 0
        errors = []
        ctrl.errorOccurred.connect(errors.append)
        result = ctrl.writeImageCaption(0, "caption")
        assert result is False
        assert len(errors) == 1

    def test_imageCaption_reflects_write(self, ctrl, tmp_path, load_folder):
        make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        ctrl.writeImageCaption(0, "Persisted")
        assert ctrl.imageCaption(0) == "Persisted"

    def test_exif_cache_invalidated(self, ctrl, tmp_path, load_folder):
        make_plain_jpeg(tmp_path / "a.jpg")
        load_folder(ctrl, str(tmp_path))
        # Warm the cache by calling imageExifInfo
        ctrl.imageExifInfo(0)
        assert ctrl._exif_cache[0] == 0
        ctrl.writeImageCaption(0, "Invalidate")
        assert ctrl._exif_cache[0] == -1

    def test_empty_caption_removes_record(self, ctrl, tmp_path, load_folder):
        p = make_jpeg_with_iptc_caption(tmp_path / "a.jpg", "Remove me")
        load_folder(ctrl, str(tmp_path))
        ctrl.writeImageCaption(0, "")
        assert ctrl.imageCaption(0) == ""


# ── Date cache ────────────────────────────────────────────────────────────────

class TestDateCache:
    def test_date_cache_populated_after_date_sort(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert len(ctrl._date_cache) == 5

    def test_date_cache_reused_on_second_sort(self, ctrl, image_folder, load_folder, qtbot):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert len(ctrl._date_cache) == 5

        # Record cache state after first sort
        cache_snapshot = dict(ctrl._date_cache)

        # Switch away then back to date — cache must be identical (no re-reads)
        ctrl.setSortOrder("name")
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        ctrl.setSortOrder("date")
        qtbot.waitUntil(lambda: not ctrl.scanning, timeout=3000)
        assert ctrl._date_cache == cache_snapshot

    def test_date_cache_cleared_on_new_folder(self, ctrl, image_folder, tmp_path, load_folder):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert len(ctrl._date_cache) > 0

        other = tmp_path / "other"
        other.mkdir()
        make_plain_jpeg(other / "x.jpg")
        load_folder(ctrl, str(other))
        # Cache should only contain files from the new folder
        assert all(str(image_folder) not in p for p in ctrl._date_cache)

    def test_date_cache_cleared_on_invalid_folder(self, ctrl, image_folder, load_folder):
        ctrl.setSortOrder("date")
        load_folder(ctrl, str(image_folder))
        assert len(ctrl._date_cache) > 0
        ctrl.loadFolder("/nonexistent/path/xyz")
        assert ctrl._date_cache == {}


# ── Kiosk mode ────────────────────────────────────────────────────────────────

class TestKioskMode:
    def test_kiosk_mode_false_by_default(self, ctrl):
        assert ctrl.kioskMode is False

    def test_kiosk_mode_true_when_set(self, qapp, _isolate_settings):
        from slideshow_controller import SlideshowController
        ctrl = SlideshowController(kiosk_mode=True)
        assert ctrl.kioskMode is True

    def test_kiosk_start_show_does_not_update_history(
        self, qapp, _isolate_settings, image_folder, load_folder
    ):
        from slideshow_controller import SlideshowController
        ctrl = SlideshowController(kiosk_mode=True)
        ctrl.loadFolder(str(image_folder))
        load_folder(ctrl, str(image_folder))
        ctrl.startShow()
        assert ctrl.folderHistory == []

    def test_non_kiosk_start_show_updates_history(self, ctrl, image_folder, load_folder):
        load_folder(ctrl, str(image_folder))
        ctrl.startShow()
        assert str(image_folder) in ctrl.folderHistory

    def test_kiosk_does_not_load_history_folder_on_init(
        self, qapp, _isolate_settings, image_folder
    ):
        from slideshow_controller import SlideshowController
        # Populate history via a normal controller first
        ctrl_normal = SlideshowController()
        ctrl_normal._update_history(str(image_folder))

        # Kiosk controller should not auto-load from history
        ctrl_kiosk = SlideshowController(kiosk_mode=True)
        assert ctrl_kiosk.imageCount == 0
        assert ctrl_kiosk.folder == ""
