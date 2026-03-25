// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Popup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay.width - 32, 680)
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
                    text: qsTr("—  HELP")
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
                text: qsTr("A full-screen photo slideshow viewer. Browse to a folder, configure transitions and sort order, then press ↵ to start. Control the slideshow using your keyboard or a smartphone with the built-in remote.")
                color: Theme.textSecondary
                font.pixelSize: 13
                wrapMode: Text.Wrap
                lineHeight: 1.4
            }

            // ── License ───────────────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                text: "© 2026 Sebastian Schäfer  ·  MIT License with Commons Clause"
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
                        text: qsTr("SETTINGS PAGE")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                        bottomPadding: 2
                    }

                    Repeater {
                        model: [
                            { keys: ["T"],   desc: qsTr("Cycle transition")    },
                            { keys: ["S"],   desc: qsTr("Cycle sort order")    },
                            { keys: ["L"],   desc: qsTr("Toggle loop")         },
                            { keys: ["A"],   desc: qsTr("Toggle autoplay")     },
                            { keys: ["B"],   desc: qsTr("Browse folder")       },
                            { keys: ["R"],   desc: qsTr("Star rating filter")  },
                            { keys: ["↵"],   desc: qsTr("Start / resume slideshow") },
                            { keys: ["V"],   desc: qsTr("Advanced settings")   },
                            { keys: ["F"],   desc: qsTr("Toggle fullscreen")   },
                            { keys: ["Esc"], desc: qsTr("Quit dialog")         },
                            { keys: ["?"],   desc: qsTr("Help")                }
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
                        text: qsTr("IN SLIDESHOW")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                        bottomPadding: 2
                    }

                    Repeater {
                        model: [
                            { keys: ["←","→"], desc: qsTr("Navigate")          },
                            { keys: ["Space"],  desc: qsTr("Play / pause")      },
                            { keys: ["F"],      desc: qsTr("Toggle fullscreen") },
                            { keys: ["I"],      desc: qsTr("Toggle info HUD")   },
                            { keys: ["J"],      desc: qsTr("Jump to image")     },
                            { keys: ["P"],      desc: qsTr("Panorama mode")     },
                            { keys: ["Esc"],    desc: qsTr("Exit slideshow")         },
                            { keys: ["?"],      desc: qsTr("Help")              }
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
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Press"); color: Theme.textGhost; font.pixelSize: 11 }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "?" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("or"); color: Theme.textGhost; font.pixelSize: 11 }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("to close"); color: Theme.textGhost; font.pixelSize: 11 }
            }
        }
    }
}
