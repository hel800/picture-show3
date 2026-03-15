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
                text: "SMARTPHONE REMOTE"
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
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            text: "Scan with your phone to open the remote"
            color: Theme.textMuted
            font.pixelSize: 11
        }
    }
}
