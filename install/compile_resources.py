# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
compile_resources.py — compile resources.qrc into resources_rc.py

Run once before building with PyInstaller (after make_icon.py):
    python install/compile_resources.py

Requires pyside6-rcc (bundled with PySide6).
Output: resources_rc.py  (project root, auto-detected by PyInstaller)
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
QRC  = ROOT / "resources.qrc"
OUT  = ROOT / "resources_rc.py"

# pyside6-rcc lives alongside the Python executable (e.g. .venv/Scripts/)
RCC = Path(sys.executable).parent / "pyside6-rcc"

subprocess.run([str(RCC), str(QRC), "-o", str(OUT)], check=True)
print(f"Created {OUT}")
