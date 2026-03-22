#!/usr/bin/env python3
# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
Compile all .ts translation files to .qm so they are available in dev mode.

Usage:
    python translations/compile.py
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
TRANSLATIONS_DIR = Path(__file__).parent


def _find_tool(name: str) -> str | None:
    """Find a PySide6 CLI tool in the project venv or system PATH."""
    for venv_dir in [ROOT / ".venv", ROOT / "venv"]:
        for scripts in ["Scripts", "bin"]:
            for suffix in ["", ".exe"]:
                candidate = venv_dir / scripts / (name + suffix)
                if candidate.is_file():
                    return str(candidate)
    return shutil.which(name)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    lrelease = _find_tool("pyside6-lrelease")
    if not lrelease:
        print("ERROR: pyside6-lrelease not found. Activate your venv first.")
        sys.exit(1)

    ts_files = sorted(TRANSLATIONS_DIR.glob("picture-show3_*.ts"))
    if not ts_files:
        print("No .ts files found in", TRANSLATIONS_DIR)
        sys.exit(0)

    print(f"Compiling {len(ts_files)} translation file(s)...\n")

    ok = True
    for ts in ts_files:
        lang = ts.stem.removeprefix("picture-show3_")
        result = subprocess.run([lrelease, str(ts)], capture_output=True, text=True)
        if result.returncode == 0:
            qm = ts.with_suffix(".qm")
            print(f"  [{lang}]  → {qm.name}")
        else:
            print(f"  [{lang}]  ERROR: {result.stderr.strip()}")
            ok = False

    if ok:
        print("\nDone. Restart the app to apply changes.")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
