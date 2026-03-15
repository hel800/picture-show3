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
