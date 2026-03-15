# This file is part of picture-show3.
# Copyright (C) 2026  Sebastian Schäfer
#
# picture-show3 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# picture-show3 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with picture-show3.  If not, see <https://www.gnu.org/licenses/>.
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
