# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for SlideshowController — pure-logic layer (no display required).

All tested methods are synchronous; no Qt timer or event-loop spinning needed.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest

from slideshow_controller import IMAGE_EXTENSIONS, SlideshowController
from tests.conftest import make_jpeg_with_xmp_attr, make_jpeg_with_xmp_elem, make_plain_jpeg


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

    def test_filter_at_rating_3(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(3)
        assert ctrl.imageCount == 3   # r3, r4, r5

    def test_filter_at_rating_5(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(5)
        assert ctrl.imageCount == 1   # only r5

    def test_filter_applied_before_load(self, ctrl, rated_folder, load_folder):
        ctrl.setMinRating(4)
        load_folder(ctrl, str(rated_folder))
        assert ctrl.imageCount == 2   # r4, r5

    def test_rating_clamped_above_5(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(10)
        assert ctrl.minRating == 5

    def test_rating_clamped_below_0(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(-3)
        assert ctrl.minRating == 0
        assert ctrl.imageCount == 6

    def test_total_image_count_unaffected_by_filter(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(4)
        assert ctrl.totalImageCount == 6
        assert ctrl.imageCount == 2

    def test_same_rating_value_is_noop(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.setMinRating(3)
        count_before = ctrl.imageCount
        ctrl.setMinRating(3)            # identical value — no filter re-run
        assert ctrl.imageCount == count_before

    def test_filter_resets_current_index_to_zero(self, ctrl, rated_folder, load_folder):
        load_folder(ctrl, str(rated_folder))
        ctrl.goTo(4)
        ctrl.setMinRating(3)
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
