# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
compile_resources.py — compile resources.qrc → resources_rc.py and .ts → .qm

Run once before building with PyInstaller (after make_icon.py):
    python install/windows/compile_resources.py

Requires pyside6-rcc and pyside6-lrelease (bundled with PySide6).
Outputs:
  resources_rc.py          (project root)
  translations/*.qm        (one per .ts file in translations/)
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
QRC  = ROOT / "resources.qrc"
OUT  = ROOT / "resources_rc.py"

# pyside6-rcc / pyside6-lrelease live alongside the Python executable
SCRIPTS = Path(sys.executable).parent
RCC      = SCRIPTS / "pyside6-rcc"
LRELEASE = SCRIPTS / "pyside6-lrelease"

# ── 1. Compile Qt resources ─────────────────────────────────────────────────
subprocess.run([str(RCC), str(QRC), "-o", str(OUT)], check=True)
print(f"Created {OUT}")

# ── 2. Compile translations ─────────────────────────────────────────────────
ts_files = sorted((ROOT / "translations").glob("*.ts"))
if ts_files:
    for ts in ts_files:
        qm = ts.with_suffix(".qm")
        subprocess.run([str(LRELEASE), str(ts), "-qm", str(qm)], check=True)
        print(f"Created {qm.relative_to(ROOT)}")
else:
    print("No .ts files found in translations/ — skipping lrelease")
