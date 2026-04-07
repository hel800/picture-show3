# Building the Linux AppImage

picture-show3 ships as a self-contained [AppImage](https://appimage.org/) on Linux —
a single executable file that runs on any modern x86-64 distribution without installation.

The build pipeline is:
1. Render `img/icon.svg` → `img/icon.png` (256 × 256)
2. Compile QML + SVG assets into `resources_rc.py` via `pyside6-rcc`
3. Bundle everything with **PyInstaller** into a onedir package
4. Wrap the bundle in an **AppDir** and pack it with **appimagetool**

---

## Portability and the Ubuntu 22.04 requirement

AppImages link against the host system's glibc. Because glibc is
**forward-compatible but not backward-compatible**, an AppImage built on a
newer distro will refuse to run on an older one.

Building on **Ubuntu 22.04 LTS** (glibc 2.35) hits the sweet spot: broad
compatibility with any distro released since ~2020, while still being able to
install Python 3.14 and PySide6 ≥ 6.7 from upstream sources.

---

## Setting up Ubuntu 22.04 on Fedora with distrobox

[distrobox](https://distrobox.it/) runs any distro as a rootless container
while mounting your home directory — you build inside Ubuntu but work directly
on your normal project files.

```bash
# Install distrobox (Fedora ships it in the default repos)
sudo dnf install distrobox

# Create an Ubuntu 22.04 container (one-time, pulls ~30 MB)
distrobox create --name ubuntu22 --image ubuntu:22.04

# Enter it — your home directory is already mounted
distrobox enter ubuntu22
```

All following commands run **inside the distrobox shell**.

---

## One-time setup inside the Ubuntu 22.04 box

### 1. Install system packages

```bash
sudo apt update
sudo apt install -y \
    software-properties-common \
    libgl1 libglib2.0-0 \
    libfontconfig1 libfreetype6 \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrender1 \
    libxkbcommon0 libxkbcommon-x11-0 \
    libegl1 libdbus-1-3
```

These are the runtime X11/GL/font libraries that Qt requires. They are **not
bundled** by PyInstaller — the AppImage relies on the host providing them
(they are universally available on any desktop Linux system).

### 2. Install Python 3.14

Ubuntu 22.04 ships Python 3.10. Install 3.14 from the deadsnakes PPA:

```bash
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.14 python3.14-venv python3.14-dev
```

### 3. Create a virtual environment and install deps

```bash
cd ~/dev/picture-show3        # your project directory (already mounted)

python3.14 -m venv .venv-linux
source .venv-linux/bin/activate

pip install -r requirements.txt
pip install -r install/linux/requirements-build.txt
```

### 4. Install appimagetool

```bash
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
    -O ~/.local/bin/appimagetool
chmod +x ~/.local/bin/appimagetool
```

> **Note:** `~/.local/bin` must be on your `PATH`. Add
> `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` if it isn't.

---

## Building

With the virtual environment active and from the project root:

```bash
source .venv-linux/bin/activate   # if not already active
python install/linux/build.py
```

The script runs all steps automatically and prints progress. On a typical
laptop the full build takes about 2–4 minutes.

**Output:**
```
install/linux/dist/installer/picture-show3-<version>-x86_64.AppImage
```

### What each step does

| Step | Script / tool | Output |
|---|---|---|
| 1. Icon | `install/linux/make_icon.py` | `img/icon.png` (256 × 256) |
| 2. Resources | `install/windows/compile_resources.py` | `resources_rc.py` |
| 3. Bundle | PyInstaller + `install/linux/picture-show3.spec` | `install/linux/dist/picture-show3/` |
| 4. AppDir | `build.py` inline | `install/linux/dist/picture-show3.AppDir/` |
| 5. AppImage | `appimagetool` | `install/linux/dist/installer/*.AppImage` |

Intermediate artefacts (`build/`, the onedir bundle, the AppDir) are removed
automatically after a successful build.

---

## Manual steps

If you prefer to run each step individually:

```bash
# 1. Generate icon
python install/linux/make_icon.py

# 2. Compile resources (shared with Windows build)
python install/windows/compile_resources.py

# 3. PyInstaller
pyinstaller install/linux/picture-show3.spec \
    --distpath install/linux/dist \
    --workpath install/linux/build

# 4–5. Assemble AppDir and pack (run build.py from step 4 onward,
#       or do it by hand — see build.py for the exact file layout)
python install/linux/build.py   # safe to re-run; skips PyInstaller if dist/ exists
```

---

## Testing the AppImage

```bash
chmod +x install/linux/dist/installer/picture-show3-*.AppImage
./install/linux/dist/installer/picture-show3-*.AppImage
```

To test on a different distro, copy the file there or mount it inside another
distrobox:

```bash
distrobox create --name fedora40 --image fedora:40
distrobox enter fedora40
~/dev/picture-show3/install/linux/dist/installer/picture-show3-*.AppImage
```
