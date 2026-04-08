# Building the Linux AppImage

picture-show3 can be packaged as an [AppImage](https://appimage.org/) on Linux —
a self-contained executable that requires no installation.

The build pipeline is:
1. Render `img/icon.svg` → `img/icon.png` (256 × 256)
2. Compile QML + SVG assets into `resources_rc.py` via `pyside6-rcc`
3. Bundle everything with **PyInstaller** into a onedir package
4. Wrap the bundle in an **AppDir** and pack it with **appimagetool**

---

## Cross-distro portability — what works and what doesn't

AppImages solve the **glibc** portability problem by building on an old distro
(Ubuntu 22.04, glibc 2.35 → runs on any distro since ~2020). However,
picture-show3 uses **Qt Quick** for GPU-accelerated rendering, which introduces
a second problem: the OpenGL/EGL/Vulkan stack must match the host's GPU drivers.

In practice:
- An AppImage built on **Ubuntu 22.04** runs correctly on Ubuntu and Debian-based distros.
- The same AppImage **fails to initialize OpenGL** on Fedora, because the
  Qt libraries compiled on Ubuntu cannot work with Fedora's Mesa/EGL/Vulkan
  stack, even when the bundled GPU libs are excluded from the bundle.
- An AppImage built **on Fedora** runs correctly on Fedora.

**Recommendation:** build the AppImage on your primary target distro.
If you need to support multiple distros, build once per distro in CI
(e.g. one GitHub Actions job on `ubuntu-22.04`, one on `fedora`).

---

## Option A: Build on Fedora (recommended for Fedora users)

No distrobox needed — build directly on the host.

### 1. Check Python 3.14

```bash
python3.14 --version
```

If not available:
```bash
sudo dnf install python3.14
```

### 2. Install build tools

```bash
sudo dnf install binutils
```

### 3. Set up virtual environment

From the project root:

```bash
python3.14 -m venv .venv-linux
source .venv-linux/bin/activate
pip install -r requirements.txt
pip install -r install/linux/requirements-build.txt
```

### 4. Install appimagetool

```bash
mkdir -p ~/.local/bin
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
    -O ~/.local/bin/appimagetool
chmod +x ~/.local/bin/appimagetool
# ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"
```

### 5. Build

```bash
source .venv-linux/bin/activate
python install/linux/build.py
```

---

## Option B: Build on Ubuntu 22.04 via distrobox (for Ubuntu/Debian targets)

[distrobox](https://distrobox.it/) runs any distro as a rootless container
while mounting your home directory — you build inside Ubuntu but work directly
on your normal project files.

### 1. Create the distrobox

```bash
sudo dnf install distrobox

distrobox create --name ubuntu22 --image ubuntu:22.04
distrobox enter ubuntu22
```

All following commands run **inside the distrobox shell**.

### 2. Install system packages

```bash
sudo apt update
sudo apt install -y \
    software-properties-common \
    binutils \
    libfuse2 \
    libgl1 libglib2.0-0 \
    libfontconfig1 libfreetype6 \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrender1 \
    libxkbcommon0 libxkbcommon-x11-0 libxcb-cursor0 \
    libegl1 libdbus-1-3
```

> **`libfuse2`** is required to run `appimagetool` inside the container
> (appimagetool is itself an AppImage). **`binutils`** is required by PyInstaller.
> **`libxcb-cursor0`** is required by Qt's xcb platform plugin.

### 3. Install Python 3.14

Ubuntu 22.04 ships Python 3.10. Install 3.14 from the deadsnakes PPA:

```bash
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.14 python3.14-venv python3.14-dev
```

### 4. Create a virtual environment and install deps

From the project root (already mounted from the host):

```bash
python3.14 -m venv .venv-linux
source .venv-linux/bin/activate

pip install -r requirements.txt
pip install -r install/linux/requirements-build.txt
```

### 5. Install appimagetool

```bash
mkdir -p ~/.local/bin
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
    -O ~/.local/bin/appimagetool
chmod +x ~/.local/bin/appimagetool
export PATH="$HOME/.local/bin:$PATH"
```

### 6. Build

```bash
source .venv-linux/bin/activate
python install/linux/build.py
```

> **Note:** The build script passes `APPIMAGE_EXTRACT_AND_RUN=1` to appimagetool
> automatically. This is required inside containers where FUSE is not available —
> it makes appimagetool extract itself to a temp dir instead of mounting via FUSE.

---

## Build output

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

## Testing the AppImage

```bash
chmod +x install/linux/dist/installer/picture-show3-*.AppImage
./install/linux/dist/installer/picture-show3-*.AppImage
```

Make sure FUSE is installed on the host (required to mount the AppImage):

```bash
sudo dnf install fuse fuse-libs   # Fedora
sudo apt install fuse             # Ubuntu/Debian
```

---

## Known limitations

- **Cross-distro GPU rendering**: A Qt Quick AppImage built on Ubuntu will fail
  to initialize OpenGL/EGL on Fedora (and vice versa), even with GPU libraries
  excluded from the bundle. Build on your target distro.
- **Software rendering fallback**: Running with `QT_QUICK_BACKEND=software`
  works everywhere but disables GPU-accelerated transitions and blur effects.
- **Flatpak as an alternative**: Flatpak solves the GPU problem via its sandboxed
  Mesa runtime, but restricts filesystem access to `$HOME` by default —
  photos on `/mnt/...` or `/run/media/...` network/USB drives would require
  additional `--filesystem` permissions.
