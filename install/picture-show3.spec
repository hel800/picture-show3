# picture-show3.spec
#
# Build with (from the project root):
#   python install/make_icon.py           # only needed once, or when icon.svg changes
#   python install/compile_resources.py   # rerun whenever any QML or img/ file changes
#   pyinstaller install/picture-show3.spec
#
# Output: dist\picture-show3\picture-show3.exe  (onedir bundle)

import os
from PyInstaller.utils.hooks import collect_data_files

block_cipher = None

# Project root is one level above this spec file
ROOT = os.path.normpath(os.path.join(SPECPATH, ".."))

# ── Collect only the QML modules actually used by this app ────────────────────
# Collecting the entire Qt/qml tree (~300-400 MB) is wasteful.
# This app uses only: QtQuick, QtQuick.Controls (Basic), QtQuick.Layouts,
# QtQuick.Dialogs, QtQml (base), and Qt.labs.platform (via Dialogs).
# Each subdir contains .qml, qmldir, and the type-plugin DLLs.
_QML_SUBDIRS = [
    "Qt/qml/QtQuick",
    "Qt/qml/QtQml",
    "Qt/qml/Qt/labs",        # Qt.labs.platform used by QtQuick.Dialogs
    "Qt/qml/QtCore",         # small; some Controls internals reference it
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
        # QML and img/ are embedded in resources_rc.py (compiled by compile_resources.py).
        # Only the PySide6 QML runtime modules are needed as loose files.
        *pyside6_qml_datas,
    ],
    hiddenimports=[
        # PySide6 modules not always auto-detected via static import analysis
        "PySide6.QtCore",
        "PySide6.QtGui",
        "PySide6.QtQml",
        "PySide6.QtQuick",
        "PySide6.QtQuickControls2",
        "PySide6.QtQuickTemplates2",
        "PySide6.QtNetwork",
        "PySide6.QtSvg",
        "PySide6.QtWidgets",
        # Pillow decoders that may not be picked up automatically
        "PIL._imaging",
        "PIL.Image",
        "PIL.JpegImagePlugin",
        "PIL.PngImagePlugin",
        "PIL.WebPImagePlugin",
        "PIL.TiffImagePlugin",
        "PIL.GifImagePlugin",
        "PIL.BmpImagePlugin",
        # qrcode
        "qrcode",
        "qrcode.image.pil",
        # Qt resource module (compiled from resources.qrc by compile_resources.py)
        "resources_rc",
    ],
    hookspath=[],
    hooksconfig={
        # Tell PyInstaller's PySide6 hook which Qt modules we use so it pulls
        # in the correct Qt DLLs and plugins automatically.
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
        # Heavy stdlib / third-party modules not used
        "tkinter", "unittest",
        "xmlrpc", "ftplib", "imaplib", "poplib", "smtplib", "telnetlib",
        "doctest", "pdb", "profile", "pstats", "cProfile",
        "difflib", "pickletools", "shelve", "dbm",
        "curses", "readline", "rlcompleter",
        "turtle", "antigravity", "this",
        "matplotlib", "numpy", "scipy", "pandas",
        "IPython", "jupyter",
        # Unused PySide6 / Qt modules
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

# ── Strip unwanted Qt binaries and data ───────────────────────────────────────
# PyInstaller's PySide6 hook pulls in every Qt DLL regardless of `excludes`.
# We explicitly remove what we don't use after Analysis.
_REMOVE_DLL_PREFIXES = [
    # WebEngine — 193 MB on its own
    "qt6webenginecore", "qt6webenginequick", "qt6webenginequickdelegatesqml",
    # PDF
    "qt6pdf", "qt6pdfquick",
    # 3D  (Qt63D* and Qt6Quick3D*)
    "qt63d", "qt6quick3d",
    # Charts, DataVisualization, Graphs
    "qt6charts", "qt6chartsqml", "qt6datavisualization", "qt6datavisualizationqml", "qt6graphs",
    # Multimedia
    "qt6multimedia", "qt6multimediaquick",
    # Location, Positioning
    "qt6location", "qt6positioning", "qt6positioningquick",
    # Sensors
    "qt6sensors", "qt6sensorsquick",
    # VirtualKeyboard
    "qt6virtualkeyboard", "qt6virtualkeyboardqml", "qt6virtualkeyboardsettings",
    # RemoteObjects, Scxml, StateMachine
    "qt6remoteobjects", "qt6remoteobjectsqml",
    "qt6scxml", "qt6scxmlqml",
    "qt6statemachine", "qt6statemachineqml",
    # TextToSpeech
    "qt6texttospeech",
    # Web channel / sockets / view
    "qt6webchannel", "qt6webchannelquick", "qt6websockets",
    "qt6webview", "qt6webviewquick",
    # SpatialAudio
    "qt6spatialaudio",
    # Test, Sql
    "qt6test", "qt6quicktest", "qt6sql",
    # Unused Controls styles (app uses Basic only)
    "qt6quickcontrols2imagine", "qt6quickcontrols2imaginestyleimpl",
    "qt6quickcontrols2material", "qt6quickcontrols2materialstyleimpl",
    "qt6quickcontrols2fusion", "qt6quickcontrols2fusionstyleimpl",
    "qt6quickcontrols2universal", "qt6quickcontrols2universalstyleimpl",
    "qt6quickcontrols2fluentwinui3styleimpl",
    "qt6quickcontrols2windowsstyleimpl",
]

def _exclude_bin(name: str) -> bool:
    n = name.lower().replace("\\", "/").split("/")[-1]
    return any(n.startswith(p) for p in _REMOVE_DLL_PREFIXES)

a.binaries = [b for b in a.binaries if not _exclude_bin(b[0])]

# Strip translations — the app has no localization
a.datas = [
    d for d in a.datas
    if "/translations/" not in d[0].replace("\\", "/").lower()
]

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,          # onedir: binaries go in the COLLECT step
    name="picture-show3",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,                       # compress with UPX if available
    console=False,                  # no console window (--windowed)
    icon=os.path.join(ROOT, "img", "icon.ico"),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="picture-show3",           # output folder: dist\picture-show3\
)
