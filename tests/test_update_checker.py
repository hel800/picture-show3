# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Tests for UpdateChecker — version comparison logic and signal emission.

Network calls are patched with unittest.mock so no real HTTP requests are made.
"""
from __future__ import annotations

import io
import json
from unittest.mock import MagicMock, patch

import pytest

from update_checker import UpdateChecker, _version_tuple


# ── _version_tuple ────────────────────────────────────────────────────────────

class TestVersionTuple:
    def test_plain_version(self):
        assert _version_tuple("1.0") == (1, 0)

    def test_v_prefix(self):
        assert _version_tuple("v1.2.3") == (1, 2, 3)

    def test_beta_suffix_stripped(self):
        assert _version_tuple("0.9 beta") == (0, 9)

    def test_v_prefix_and_suffix(self):
        assert _version_tuple("v0.9 beta") == (0, 9)

    def test_single_digit(self):
        assert _version_tuple("2") == (2,)

    def test_empty_string(self):
        assert _version_tuple("") == (0,)

    def test_no_digits(self):
        assert _version_tuple("beta") == (0,)

    def test_capped_at_three_components(self):
        assert _version_tuple("1.2.3.4.5") == (1, 2, 3)

    def test_same_version_not_newer(self):
        assert not (_version_tuple("v0.9") > _version_tuple("0.9 beta"))

    def test_newer_minor(self):
        assert _version_tuple("v1.0") > _version_tuple("0.9 beta")

    def test_older_not_newer(self):
        assert not (_version_tuple("v0.8") > _version_tuple("0.9 beta"))

    def test_patch_version_newer(self):
        assert _version_tuple("1.0.1") > _version_tuple("1.0.0")


# ── UpdateChecker — signal emission ──────────────────────────────────────────

def _fake_response(tag: str, html_url: str = "https://example.com") -> MagicMock:
    """Build a mock urllib response returning a GitHub-style JSON payload."""
    body = json.dumps({"tag_name": tag, "html_url": html_url}).encode()
    mock = MagicMock()
    mock.__enter__ = lambda s: s
    mock.__exit__ = MagicMock(return_value=False)
    mock.read.return_value = body
    return mock


class TestUpdateCheckerSignal:
    def test_emits_when_newer_version_available(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        with patch("urllib.request.urlopen", return_value=_fake_response("v1.0")):
            checker.check("0.9 beta")
            qtbot.waitUntil(lambda: len(received) == 1, timeout=3000)

        assert received == ["1.0"]

    def test_no_emit_when_same_version(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        with patch("urllib.request.urlopen", return_value=_fake_response("v0.9")):
            checker.check("0.9 beta")
            # Give the thread time to finish
            import time; time.sleep(0.3)
            qtbot.waitSignal(checker.updateAvailable, timeout=500, raising=False)

        assert received == []

    def test_no_emit_when_older_version(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        with patch("urllib.request.urlopen", return_value=_fake_response("v0.8")):
            checker.check("0.9 beta")
            import time; time.sleep(0.3)
            qtbot.waitSignal(checker.updateAvailable, timeout=500, raising=False)

        assert received == []

    def test_no_emit_on_network_error(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        with patch("urllib.request.urlopen", side_effect=OSError("network unavailable")):
            checker.check("0.9 beta")
            import time; time.sleep(0.3)
            qtbot.waitSignal(checker.updateAvailable, timeout=500, raising=False)

        assert received == []

    def test_no_emit_on_malformed_json(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        mock = MagicMock()
        mock.__enter__ = lambda s: s
        mock.__exit__ = MagicMock(return_value=False)
        mock.read.return_value = b"not json {"

        with patch("urllib.request.urlopen", return_value=mock):
            checker.check("0.9 beta")
            import time; time.sleep(0.3)
            qtbot.waitSignal(checker.updateAvailable, timeout=500, raising=False)

        assert received == []

    def test_emitted_version_strips_v_prefix(self, qtbot):
        checker = UpdateChecker()
        received: list[str] = []
        checker.updateAvailable.connect(received.append)

        with patch("urllib.request.urlopen", return_value=_fake_response("v2.0.1")):
            checker.check("1.0")
            qtbot.waitUntil(lambda: len(received) == 1, timeout=3000)

        assert received[0] == "2.0.1"
