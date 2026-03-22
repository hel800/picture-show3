#!/usr/bin/env python3
# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Update all .ts translation files with new/changed strings from source code,
then report how many strings are still untranslated in each file.

Usage:
    python translations/update.py
"""
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).parent.parent
TRANSLATIONS_DIR = Path(__file__).parent

# Source files that contain translatable strings
QML_DIR   = ROOT / "qml"
PY_SOURCES = [ROOT / "slideshow_controller.py"]


def _find_tool(name: str) -> str | None:
    """Find a PySide6 CLI tool in the project venv or system PATH."""
    for venv_dir in [ROOT / ".venv", ROOT / "venv"]:
        for scripts in ["Scripts", "bin"]:
            for suffix in ["", ".exe"]:
                candidate = venv_dir / scripts / (name + suffix)
                if candidate.is_file():
                    return str(candidate)
    return shutil.which(name)


def _count_unfinished(ts_path: Path) -> list[str]:
    """Return a list of source strings that are still unfinished."""
    tree = ET.parse(ts_path)
    unfinished = []
    for msg in tree.getroot().iter("message"):
        trans = msg.find("translation")
        if trans is not None and trans.get("type") == "unfinished":
            src = msg.findtext("source", "")
            unfinished.append(src)
    return unfinished


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    lupdate = _find_tool("pyside6-lupdate")
    if not lupdate:
        print("ERROR: pyside6-lupdate not found. Activate your venv first.")
        sys.exit(1)

    qml_files  = sorted(QML_DIR.glob("*.qml"))
    source_files = [str(f) for f in qml_files] + [str(f) for f in PY_SOURCES]
    ts_files = sorted(TRANSLATIONS_DIR.glob("picture-show3_*.ts"))

    if not ts_files:
        print("No .ts files found in", TRANSLATIONS_DIR)
        sys.exit(0)

    print(f"Updating {len(ts_files)} translation file(s) from {len(source_files)} source file(s)...\n")

    cmd = [lupdate] + source_files + ["-ts"] + [str(f) for f in ts_files]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("lupdate failed:\n" + result.stderr)
        sys.exit(1)

    # Report
    any_unfinished = False
    for ts in ts_files:
        lang = ts.stem.removeprefix("picture-show3_")
        missing = _count_unfinished(ts)
        if missing:
            any_unfinished = True
            print(f"  [{lang}]  {len(missing)} unfinished:")
            for s in missing:
                preview = s[:60] + "…" if len(s) > 60 else s
                print(f"           · {preview}")
        else:
            print(f"  [{lang}]  ✓ complete")

    if any_unfinished:
        print("\nEdit the .ts file(s), then run  python translations/compile.py")
    else:
        print("\nAll translations complete. Run  python translations/compile.py")


if __name__ == "__main__":
    main()
