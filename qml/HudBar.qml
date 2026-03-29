// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: root

    property real   hudScale      : 1.0
    property bool   hudVisible    : false
    property string hudCaption    : ""
    property int    hudRating     : 0
    property bool   exifPanelOpen : false   // set by parent when ExifPanel is open

    anchors.left:   parent.left
    anchors.right:  parent.right
    anchors.bottom: parent.bottom
    height: Math.round(52 * hudScale)
    color: Qt.rgba(0, 0, 0, 0.65)
    opacity: 0
    z: 10

    state: hudVisible ? "shown" : "hidden"
    states: [
        State { name: "shown";  PropertyChanges { target: root; opacity: 1 } },
        State { name: "hidden"; PropertyChanges { target: root; opacity: 0 } }
    ]
    transitions: Transition {
        NumberAnimation { property: "opacity"; duration: 300 }
    }

    // Subtle top border line
    Rectangle {
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    RowLayout {
        anchors { fill: parent; leftMargin: Math.round(20 * hudScale); rightMargin: Math.round(20 * hudScale) }
        spacing: Math.round(6 * hudScale)

        // index counter
        Text {
            text: (controller.currentIndex + 1) + " / " + controller.imageCount
            color: Theme.textPrimary; font.pixelSize: Math.round(16 * hudScale); font.weight: Font.Bold
        }

        // filename
        Text { text: "≡"; color: Theme.textSubtle; font.pixelSize: Math.round(14 * hudScale); Layout.leftMargin: Math.round(10 * hudScale) }
        Text {
            text: controller.imagePath(controller.currentIndex).split(/[/\\]/).pop()
            color: Theme.textSecondary; font.pixelSize: Math.round(13 * hudScale)
            elide: Text.ElideMiddle
            Layout.maximumWidth: Math.round(220 * hudScale)
        }

        // caption — always-present filler; text shown only when available
        Text { text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * hudScale); visible: hudCaption.length > 0 }
        Text { text: "✎"; color: Theme.textSubtle;   font.pixelSize: Math.round(13 * hudScale); visible: hudCaption.length > 0 }
        Item {
            Layout.fillWidth: true
            implicitHeight: captionText.implicitHeight
            Text {
                id: captionText
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width
                text: hudCaption
                color: Theme.textSecondary; font.pixelSize: Math.round(13 * hudScale)
                visible: hudCaption.length > 0
                elide: Text.ElideRight
            }
        }

        // star rating (hidden when 0 / unset)
        Row {
            spacing: Math.round(2 * hudScale)
            visible: hudRating > 0
            Repeater {
                model: 5
                ThemedIcon {
                    source: "../img/icon_star.svg"
                    size: Math.round(12 * hudScale)
                    iconColor: index < hudRating ? Theme.accentLight : Theme.starInactive
                }
            }
        }

        // date taken (hidden when unavailable)
        Text { text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * hudScale); visible: dateText.visible && captionText.truncated }
        Text { text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * hudScale); visible: hudRating > 0 && dateText.visible }
        ThemedIcon { source: "../img/icon_clock.svg"; size: Math.round(13 * hudScale); iconColor: Theme.textSubtle; visible: dateText.visible }
        Text {
            id: dateText
            text: controller.imageDateTaken(controller.currentIndex)
            color: Theme.textSubtle; font.pixelSize: Math.round(13 * hudScale)
            visible: text.length > 0
        }

        // ⌨ keyboard hints
        KeyHint { label: "F";   uiScale: hudScale; Layout.leftMargin: Math.round(10 * hudScale) }
        Text { text: qsTr("Fullscreen"); color: Theme.textDisabled; font.pixelSize: Math.round(12 * hudScale) }
        KeyHint { label: "I";   uiScale: hudScale }
        Text { text: qsTr("Info");       color: Theme.textDisabled; font.pixelSize: Math.round(12 * hudScale) }
        KeyHint { label: ",";   uiScale: hudScale }
        Text { text: qsTr("Details");    color: exifPanelOpen ? Theme.accentLight : Theme.textDisabled; font.pixelSize: Math.round(12 * hudScale) }
        KeyHint { label: "Esc"; uiScale: hudScale }
        Text { text: qsTr("Exit");       color: Theme.textDisabled; font.pixelSize: Math.round(12 * hudScale) }
    }
}
