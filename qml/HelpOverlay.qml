// This file is part of picture-show3.
// Copyright (C) 2026  Sebastian Schäfer
//
// picture-show3 is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// picture-show3 is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with picture-show3.  If not, see <https://www.gnu.org/licenses/>.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Popup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: Math.min(parent.width - 64, 660)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    leftPadding: 28; rightPadding: 28; topPadding: 24; bottomPadding: 24

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale";   from: 0.92; to: 1; duration: 250; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale";   from: 1; to: 0.92; duration: 200; easing.type: Easing.InCubic }
        }
    }

    background: Rectangle {
        radius: 20
        color: Theme.bgCard
        border.color: Theme.surface
        border.width: 1
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.6) }

    property int revealStep: -1

    onOpened: {
        keyFocus.forceActiveFocus()
        revealStep = -1
        revealTimer.start()
    }
    onClosed: {
        revealTimer.stop()
        revealStep = -1
    }

    Timer {
        id: revealTimer
        interval: 35
        repeat: true
        onTriggered: {
            root.revealStep++
            if (root.revealStep >= 11) stop()
        }
    }

    contentItem: Item {
        id: keyFocus
        focus: true
        implicitHeight: contentCol.implicitHeight

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Question) {
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_F) {
                var win = Window.window
                if (win.visibility === Window.FullScreen)
                    win.showNormal()
                else {
                    windowHelper.saveWindowed()
                    win.showFullScreen()
                }
                event.accepted = true
            }
        }

        ColumnLayout {
            id: contentCol
            width: parent.width
            spacing: 18

            // ── Title + version ───────────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "../img/logo.svg"
                    fillMode: Image.PreserveAspectFit
                    width: 180; height: 28
                    smooth: true; mipmap: true
                    sourceSize.width: 360
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "—  HELP"
                    color: Theme.accentLight
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "v" + appVersion
                color: Theme.textSubtle
                font.pixelSize: 12
                topPadding: -10
            }

            // ── Description ───────────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                text: "A full-screen photo slideshow viewer. Browse to a folder, configure transitions and sort order, then press ↵ to start. Control the show from the keyboard or from a smartphone via the built-in remote."
                color: Theme.textSecondary
                font.pixelSize: 13
                wrapMode: Text.Wrap
                lineHeight: 1.4
            }

            // ── License ───────────────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                text: "© 2026 Sebastian Schäfer  ·  Released under the GNU General Public License v3"
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            // ── Divider ───────────────────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

            // ── Keyboard shortcuts ────────────────────────────────────────────
            // Each row: fixed-width key cell so descriptions align as a column.
            //   settings key cell: 44 px (fits "Esc")
            //   in-show  key cell: 58 px (fits "← →" and "Space")
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                // Settings page column
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "SETTINGS PAGE"
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                        bottomPadding: 2
                    }

                    Repeater {
                        model: [
                            { keys: ["T"],   desc: "Cycle transition"   },
                            { keys: ["S"],   desc: "Cycle sort order"   },
                            { keys: ["L"],   desc: "Toggle loop"        },
                            { keys: ["A"],   desc: "Toggle autoplay"    },
                            { keys: ["B"],   desc: "Browse folder"      },
                            { keys: ["R"],   desc: "Star rating filter" },
                            { keys: ["↵"],   desc: "Start / resume show"},
                            { keys: ["V"],   desc: "Advanced settings"  },
                            { keys: ["F"],   desc: "Toggle fullscreen"  },
                            { keys: ["Esc"], desc: "Quit dialog"        },
                            { keys: ["?"],   desc: "Help"               }
                        ]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            opacity: index <= root.revealStep ? 1 : 0
                            scale: index <= root.revealStep ? 1.0 : 0.85
                            transformOrigin: Item.Left
                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                            Item {
                                implicitWidth: 44
                                implicitHeight: keyRow.implicitHeight
                                Row {
                                    id: keyRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Repeater {
                                        model: modelData.keys
                                        KeyHint { label: modelData }
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.desc
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                // In-show column
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "IN SHOW"
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                        bottomPadding: 2
                    }

                    Repeater {
                        model: [
                            { keys: ["←","→"], desc: "Navigate"         },
                            { keys: ["Space"],  desc: "Play / pause"     },
                            { keys: ["F"],      desc: "Toggle fullscreen"},
                            { keys: ["I"],      desc: "Toggle info HUD"  },
                            { keys: ["J"],      desc: "Jump to image"    },
                            { keys: ["Esc"],    desc: "Exit show"        },
                            { keys: ["?"],      desc: "Help"             }
                        ]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            opacity: index <= root.revealStep ? 1 : 0
                            scale: index <= root.revealStep ? 1.0 : 0.85
                            transformOrigin: Item.Left
                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                            Item {
                                implicitWidth: 58
                                implicitHeight: keyRow2.implicitHeight
                                Row {
                                    id: keyRow2
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Repeater {
                                        model: modelData.keys
                                        KeyHint { label: modelData }
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.desc
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

            // ── Close hint ────────────────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Press"; color: Theme.textGhost; font.pixelSize: 11 }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "?" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "or"; color: Theme.textGhost; font.pixelSize: 11 }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "to close"; color: Theme.textGhost; font.pixelSize: 11 }
            }
        }
    }
}
