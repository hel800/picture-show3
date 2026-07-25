# picture-show3.spec  (Linux)
#
# Build with (from the project root):
#   python install/linux/make_icon.py           # only needed once, or when icon.svg changes
#   python install/linux/../windows/compile_resources.py   # rerun whenever any QML or img/ file changes
#   pyinstaller install/linux/picture-show3.spec \
#       --distpath install/linux/dist --workpath install/linux/build
#
# Output: install/linux/dist/picture-show3/  (onedir bundle)

import os
from PyInstaller.utils.hooks import collect_data_files

block_cipher = None

# Project root is two levels above this spec file (install/linux/ → project root)
ROOT = os.path.normpath(os.path.join(SPECPATH, "..", ".."))

# ── Collect only the QML modules actually used by this app ────────────────────
_QML_SUBDIRS = [
    "Qt/qml/QtQuick",
    "Qt/qml/QtQml",
    "Qt/qml/Qt/labs",
    "Qt/qml/QtCore",
]
pyside6_qml_datas = []
for _subdir in _QML_SUBDIRS:
    pyside6_qml_datas += collect_data_files("PySide6", subdir=_subdir)

# ── Main analysis ─────────────────────────────────────────────────────────────
a = Analysis(
    [os.path.join(ROOT, "main.py")],
    pathex=[ROOT],
    binaries=[],
    datas=[
        *pyside6_qml_datas,
    ],
    hiddenimports=[
        "PySide6.QtCore",
        "PySide6.QtGui",
        "PySide6.QtQml",
        "PySide6.QtQuick",
        "PySide6.QtQuickControls2",
        "PySide6.QtQuickTemplates2",
        "PySide6.QtNetwork",
        "PySide6.QtSvg",
        "PySide6.QtWidgets",
        "PIL._imaging",
        "PIL.Image",
        "PIL.JpegImagePlugin",
        "PIL.PngImagePlugin",
        "PIL.WebPImagePlugin",
        "PIL.TiffImagePlugin",
        "PIL.GifImagePlugin",
        "PIL.BmpImagePlugin",
        "qrcode",
        "qrcode.image.pil",
        "resources_rc",
    ],
    hookspath=[],
    hooksconfig={
        "PySide6": {
            "qt_modules": [
                "QtCore", "QtGui", "QtQml", "QtQuick",
                "QtQuickControls2", "QtQuickTemplates2",
                "QtNetwork", "QtSvg", "QtWidgets",
            ],
        },
    },
    runtime_hooks=[],
    excludes=[
        "tkinter", "unittest",
        "xmlrpc", "ftplib", "imaplib", "poplib", "smtplib", "telnetlib",
        "doctest", "pdb", "profile", "pstats", "cProfile",
        "difflib", "pickletools", "shelve", "dbm",
        "curses", "readline", "rlcompleter",
        "turtle", "antigravity", "this",
        "matplotlib", "numpy", "scipy", "pandas",
        "IPython", "jupyter",
        "PySide6.QtWebEngine", "PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets",
        "PySide6.Qt3DCore", "PySide6.Qt3DRender", "PySide6.Qt3DInput",
        "PySide6.Qt3DAnimation", "PySide6.Qt3DExtras",
        "PySide6.QtMultimedia", "PySide6.QtMultimediaWidgets",
        "PySide6.QtBluetooth", "PySide6.QtLocation", "PySide6.QtPositioning",
        "PySide6.QtNfc", "PySide6.QtSensors", "PySide6.QtSerialPort",
        "PySide6.QtCharts", "PySide6.QtDataVisualization",
        "PySide6.QtRemoteObjects", "PySide6.QtScxml",
        "PySide6.QtTextToSpeech",
    ],
    cipher=block_cipher,
    noarchive=False,
)

# ── Strip unwanted Qt shared libraries ────────────────────────────────────────
# On Linux, Qt libs are named libQt6XYZ.so.6 — prefixes are lowercased below.
_REMOVE_SO_PREFIXES = [
    # GPU / graphics stack — must ALL come from the host to match its drivers.
    # Bundling Ubuntu's versions breaks rendering on other distros (e.g. Fedora).
    "libegl.so", "libgl.so", "libglx.so", "libgldispatch.so", "libopengl.so",
    "libvulkan.so",     # Vulkan loader — must find host ICD drivers
    "libdrm.so",        # Direct Rendering Manager
    "libgbm.so",        # Generic Buffer Manager
    # WebEngine
    "libqt6webenginecore", "libqt6webenginequick", "libqt6webenginequickdelegatesqml",
    # PDF
    "libqt6pdf", "libqt6pdfquick",
    # 3D  (libQt63DCore, libQt63DRender, libQt6Quick3D…)
    "libqt63d", "libqt6quick3d",
    # Charts, DataVisualization, Graphs
    "libqt6charts", "libqt6chartsqml",
    "libqt6datavisualization", "libqt6datavisualizationqml",
    "libqt6graphs",
    # Multimedia
    "libqt6multimedia", "libqt6multimediaquick",
    # Location, Positioning
    "libqt6location", "libqt6positioning", "libqt6positioningquick",
    # Sensors
    "libqt6sensors", "libqt6sensorsquick",
    # VirtualKeyboard
    "libqt6virtualkeyboard",
    # RemoteObjects, Scxml, StateMachine
    "libqt6remoteobjects", "libqt6remoteobjectsqml",
    "libqt6scxml", "libqt6scxmlqml",
    "libqt6statemachine", "libqt6statemachineqml",
    # TextToSpeech
    "libqt6texttospeech",
    # Web channel / sockets / view
    "libqt6webchannel", "libqt6webchannelquick",
    "libqt6websockets",
    "libqt6webview", "libqt6webviewquick",
    # SpatialAudio
    "libqt6spatialaudio",
    # Test, Sql
    "libqt6test", "libqt6quicktest", "libqt6sql",
    # Unused Controls styles (app uses Basic only)
    "libqt6quickcontrols2imagine", "libqt6quickcontrols2imaginestyleimpl",
    "libqt6quickcontrols2material", "libqt6quickcontrols2materialstyleimpl",
    "libqt6quickcontrols2fusion", "libqt6quickcontrols2fusionstyleimpl",
    "libqt6quickcontrols2universal", "libqt6quickcontrols2universalstyleimpl",
    "libqt6quickcontrols2fluentwinui3styleimpl",
]

def _exclude_bin(name: str) -> bool:
    n = name.lower().replace("\\", "/").split("/")[-1]
    return any(n.startswith(p) for p in _REMOVE_SO_PREFIXES)

a.binaries = [b for b in a.binaries if not _exclude_bin(b[0])]

# Strip translations
a.datas = [
    d for d in a.datas
    if "/translations/" not in d[0].replace("\\", "/").lower()
]

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="picture-show3",
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,         # strip debug symbols — saves ~30 % on Linux
    upx=False,          # skip UPX: can break .so files on Linux
    console=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=True,
    upx=False,
    upx_exclude=[],
    name="picture-show3",
)
