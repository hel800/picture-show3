// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

BasePopup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: 320
    height: contentCol.implicitHeight + 48
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        radius: 20
        color: Theme.bgCard
        border.color: Theme.surface
        border.width: 1
        transform: Translate { y: root._slideOffset }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    ColumnLayout {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 16

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: qsTr("SMARTPHONE REMOTE")
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 1.4
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 28; height: 28; radius: 8
                color: closeHover.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Theme.textMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // ── QR code ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 224; height: 224
            radius: 12
            color: "white"

            Image {
                anchors { fill: parent; margins: 8 }
                source: "image://qr/" + encodeURIComponent(remoteServer.url)
                fillMode: Image.PreserveAspectFit
                smooth: false   // keep QR pixels crisp
                cache: true
            }
        }

        // ── URL label ─────────────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: remoteServer.url
            color: Theme.accentLight
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: qsTr("Scan with your phone to open the remote")
            color: Theme.textMuted
            font.pixelSize: 11
        }
    }
}
