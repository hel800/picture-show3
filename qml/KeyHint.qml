// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import "."

Rectangle {
    property string label   : ""
    property real   uiScale : 1.0

    implicitWidth:  keyLabel.implicitWidth + Math.round(10 * uiScale)
    implicitHeight: Math.round(18 * uiScale)
    radius: Math.round(4 * uiScale)
    color: Theme.surface
    border.color: Theme.textSubtle
    border.width: 1

    Text {
        id: keyLabel
        anchors.centerIn: parent
        text: parent.label
        color: Theme.textSecondary
        font.pixelSize: Math.round(11 * uiScale)
        font.weight: Font.Medium
    }
}
