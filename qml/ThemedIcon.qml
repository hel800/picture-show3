// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Effects

// Renders an SVG icon tinted to a given color via MultiEffect colorization.
// Usage:  ThemedIcon { source: "../img/icon_clock.svg"; size: 16; iconColor: Theme.textSubtle }
Item {
    property string source   : ""
    property real   size     : 16
    property color  iconColor: "white"

    implicitWidth:  size
    implicitHeight: size

    Image {
        id: img
        source: parent.source
        anchors.fill: parent
        smooth: true
        mipmap: true
        visible: false
        sourceSize.width: parent.size
        sourceSize.height: parent.size
    }
    MultiEffect {
        source: img
        anchors.fill: img
        colorization: 1.0
        colorizationColor: parent.iconColor
    }
}
