# Copyright (c) 2026 Sebastian Schäfer
# Licensed under MIT License with Commons Clause — see LICENSE for details.
"""
build.py — full Linux AppImage build pipeline for picture-show3

Reads APP_VERSION from main.py and threads it through every build step.

Usage (from the project root):
    python install/linux/build.py

Prerequisites:
    pip install -r install/linux/requirements-build.txt
    appimagetool on PATH  (download from GitHub Releases — AppImageKit)
      e.g.: wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
            chmod +x appimagetool-x86_64.AppImage
            mv appimagetool-x86_64.AppImage /usr/local/bin/appimagetool
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT  = Path(__file__).parent.parent.parent
LINUX = Path(__file__).parent

# ── Read version from main.py ─────────────────────────────────────────────────
_main_src = (ROOT / "main.py").read_text(encoding="utf-8")
_match = re.search(r'^APP_VERSION\s*=\s*["\'](.+?)["\']', _main_src, re.MULTILINE)
if not _match:
    sys.exit("ERROR: could not find APP_VERSION in main.py")

VERSION      = _match.group(1)                             # e.g. "3.2"
VERSION_SAFE = VERSION.replace(" ", "-")                   # e.g. "3.2-dev"
APPIMAGE_NAME = f"picture-show3-{VERSION_SAFE}-x86_64"    # e.g. "picture-show3-3.2-x86_64"

print(f"╔══════════════════════════════════════════╗")
print(f"  picture-show3 Linux AppImage build  v{VERSION}")
print(f"╚══════════════════════════════════════════╝\n")


def run(*args: str) -> None:
    print(f"▶ {' '.join(args)}\n")
    subprocess.run(list(args), check=True, cwd=ROOT)


def find_appimagetool() -> str:
    """Return the appimagetool executable path, or exit with an error."""
    tool = shutil.which("appimagetool")
    if tool:
        return tool
    # Common local drops
    for candidate in [
        Path.home() / ".local" / "bin" / "appimagetool",
        Path("/usr/local/bin/appimagetool"),
        LINUX / "appimagetool",
        LINUX / "appimagetool-x86_64.AppImage",
    ]:
        if candidate.is_file():
            return str(candidate)
    sys.exit(
        "ERROR: appimagetool not found on PATH.\n"
        "Download it from https://github.com/AppImage/AppImageKit/releases\n"
        "and place it on PATH or in install/linux/."
    )


# ── Step 1: Generate icon.png ─────────────────────────────────────────────────
run(sys.executable, str(LINUX / "make_icon.py"))

# ── Step 2: Compile Qt resources ─────────────────────────────────────────────
# compile_resources.py is shared with the Windows build — it's platform-agnostic.
run(sys.executable, str(LINUX.parent / "windows" / "compile_resources.py"))

# ── Step 3: PyInstaller ───────────────────────────────────────────────────────
run(
    "pyinstaller",
    str(LINUX / "picture-show3.spec"),
    "--distpath", str(LINUX / "dist"),
    "--workpath", str(LINUX / "build"),
)

# ── Step 4: Assemble AppDir ───────────────────────────────────────────────────
_bundle   = LINUX / "dist" / "picture-show3"
_appdir   = LINUX / "dist" / "picture-show3.AppDir"

if _appdir.exists():
    shutil.rmtree(_appdir)

print(f"▶ Assembling {_appdir}\n")
shutil.copytree(_bundle, _appdir)

# Required AppImage metadata
shutil.copy(LINUX / "picture-show3.desktop", _appdir / "picture-show3.desktop")
shutil.copy(ROOT  / "img" / "icon.png",      _appdir / "picture-show3.png")

_apprun_dst = _appdir / "AppRun"
shutil.copy(LINUX / "AppRun", _apprun_dst)
_apprun_dst.chmod(0o755)

# ── Step 5: Build AppImage ────────────────────────────────────────────────────
_out_dir = LINUX / "dist" / "installer"
_out_dir.mkdir(parents=True, exist_ok=True)
_appimage = _out_dir / f"{APPIMAGE_NAME}.AppImage"

appimagetool = find_appimagetool()
print(f"▶ {appimagetool} {_appdir} {_appimage}\n")
subprocess.run(
    [appimagetool, str(_appdir), str(_appimage)],
    check=True,
    cwd=ROOT,
    env={**os.environ, "ARCH": "x86_64"},
)

# ── Step 6: Clean up intermediate build artefacts ────────────────────────────
for _path in [
    LINUX / "build",          # PyInstaller work dir
    _bundle,                  # PyInstaller onedir bundle
    _appdir,                  # assembled AppDir
]:
    if _path.exists():
        print(f"▶ Removing {_path}")
        shutil.rmtree(_path)

print(f"\n✔  AppImage ready:")
print(f"   {_appimage}")
