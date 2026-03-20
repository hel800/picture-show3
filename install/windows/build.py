# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
build.py — full Windows build pipeline for picture-show3

Reads APP_VERSION from main.py and threads it through every build step so the
version only ever needs to be changed in one place.

Usage (from the project root):
    python install/windows/build.py

Prerequisites:
    pip install -r install/windows/requirements-build.txt
    Inno Setup 6 installed and iscc.exe on PATH
      (default: C:\\Program Files (x86)\\Inno Setup 6\\iscc.exe)
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT    = Path(__file__).parent.parent.parent
WINDOWS = Path(__file__).parent

# ── Read version from main.py ─────────────────────────────────────────────────
_main_src = (ROOT / "main.py").read_text(encoding="utf-8")
_match = re.search(r'^APP_VERSION\s*=\s*["\'](.+?)["\']', _main_src, re.MULTILINE)
if not _match:
    sys.exit("ERROR: could not find APP_VERSION in main.py")

VERSION       = _match.group(1)                            # e.g. "0.5 beta"
VERSION_SAFE  = VERSION.replace(" ", "-")                  # e.g. "0.5-beta"
INSTALLER_NAME = f"picture-show3-setup-{VERSION_SAFE}"    # e.g. "picture-show3-setup-0.5-beta"

print(f"╔══════════════════════════════════════════╗")
print(f"  picture-show3 Windows build  v{VERSION}")
print(f"╚══════════════════════════════════════════╝\n")


def run(*args: str) -> None:
    print(f"▶ {' '.join(args)}\n")
    subprocess.run(list(args), check=True, cwd=ROOT)


# ── Step 1: Generate icon.ico ─────────────────────────────────────────────────
run(sys.executable, str(WINDOWS / "make_icon.py"))

# ── Step 2: Compile Qt resources ─────────────────────────────────────────────
run(sys.executable, str(WINDOWS / "compile_resources.py"))

# ── Step 3: PyInstaller ───────────────────────────────────────────────────────
run(
    "pyinstaller",
    str(WINDOWS / "picture-show3.spec"),
    "--distpath", str(WINDOWS / "dist"),
    "--workpath", str(WINDOWS / "build"),
)

# ── Step 4: Inno Setup ───────────────────────────────────────────────────────
run(
    "iscc",
    f"/DMyAppVersion={VERSION}",
    f"/DOutputBaseFilename={INSTALLER_NAME}",
    str(WINDOWS / "picture-show3.iss"),
)

# ── Step 5: Clean up intermediate build artefacts ────────────────────────────
for _path in [
    WINDOWS / "build",                  # PyInstaller work dir
    WINDOWS / "dist" / "picture-show3", # PyInstaller onedir bundle
]:
    if _path.exists():
        print(f"▶ Removing {_path}")
        shutil.rmtree(_path)

print(f"\n✔  Installer ready:")
print(f"   {WINDOWS / 'dist' / 'installer' / (INSTALLER_NAME + '.exe')}")
