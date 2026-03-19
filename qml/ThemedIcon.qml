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
