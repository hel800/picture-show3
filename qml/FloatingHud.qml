// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    property real   hudScale   : 1.0
    property bool   hudVisible : false
    property string hudCaption : ""
    property int    hudRating  : 0

    anchors.fill: parent
    z: 10

    // ── Sizing ────────────────────────────────────────────────────────────────
    // height = 18 % of parent, width derived from h/w ratio 0.22,
    // clamped so width ≤ 90 % of parent width.
    readonly property real _targetH : parent.height * 0.18
    readonly property real _targetW : _targetH / 0.22
    readonly property real _maxW    : parent.width  * 0.9
    readonly property real _hudW    : Math.min(_targetW, _maxW)
    readonly property real _hudH    : _targetW <= _maxW ? _targetH : _maxW * 0.22

    // ── Transition offset (animated via states) ───────────────────────────────
    property real _yOffset: _hudH + 20

    opacity: 0

    state: hudVisible ? "shown" : "hidden"
    states: [
        State {
            name: "shown"
            PropertyChanges { target: root; opacity: 1; _yOffset: 0 }
        },
        State {
            name: "hidden"
            PropertyChanges { target: root; opacity: 0; _yOffset: root._hudH + 20 }
        }
    ]
    transitions: [
        Transition {
            to: "shown"
            ParallelAnimation {
                NumberAnimation { property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                NumberAnimation { property: "_yOffset"; duration: 320; easing.type: Easing.OutCubic }
            }
        },
        Transition {
            to: "hidden"
            ParallelAnimation {
                NumberAnimation { property: "opacity"; duration: 200; easing.type: Easing.InQuad }
                NumberAnimation { property: "_yOffset"; duration: 200; easing.type: Easing.InCubic }
            }
        }
    ]

    // ── Box ───────────────────────────────────────────────────────────────────
    Rectangle {
        id: hudBox
        width:  root._hudW
        height: root._hudH
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - Math.round(24 * root.hudScale) + root._yOffset
        radius: 18
        color:        Qt.rgba(0, 0, 0, 0.82)
        border.color: Qt.rgba(1, 1, 1, 0.25)
        border.width: 1

        RowLayout {
            anchors {
                fill: parent
                leftMargin:  Math.round(16 * root.hudScale)
                rightMargin: Math.round(16 * root.hudScale)
            }
            spacing: Math.round(10 * root.hudScale)

            // ── Counter ───────────────────────────────────────────────────────
            Text {
                text: (controller.currentIndex + 1) + " / " + controller.imageCount
                color: Theme.textPrimary
                font.pixelSize: Math.round(13 * root.hudScale)
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                width: 1; height: Math.round(14 * root.hudScale)
                color: Qt.rgba(1, 1, 1, 0.2)
                Layout.alignment: Qt.AlignVCenter
            }

            // ── Caption ───────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: captionText.implicitHeight
                clip: true

                Text {
                    id: captionText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hudCaption
                    color: Theme.textPrimary
                    font.pixelSize: Math.round(14 * root.hudScale)
                    font.weight: Font.Medium
                    // Use natural width when scrolling; wrap to container otherwise
                    width:  root.hudCaption.length > 0 ? implicitWidth : parent.width
                    elide:  Text.ElideNone
                    visible: root.hudCaption.length > 0

                    readonly property real _overflow: implicitWidth - parent.width

                    SequentialAnimation on x {
                        running: root.hudCaption.length > 0 && captionText._overflow > 0
                        loops:   Animation.Infinite
                        PauseAnimation  { duration: 1500 }
                        NumberAnimation {
                            from: 0; to: -captionText._overflow
                            duration: Math.max(1500, captionText._overflow * 25)
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation  { duration: 1000 }
                        NumberAnimation {
                            to: 0
                            duration: Math.max(1500, captionText._overflow * 25)
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            // ── Separator before meta (hidden when no meta to show) ───────────
            Rectangle {
                width: 1; height: Math.round(14 * root.hudScale)
                color: Qt.rgba(1, 1, 1, 0.2)
                Layout.alignment: Qt.AlignVCenter
                visible: root.hudRating > 0 || dateText.visible
            }

            // ── Star rating ───────────────────────────────────────────────────
            Row {
                spacing: Math.round(2 * root.hudScale)
                visible: root.hudRating > 0
                Layout.alignment: Qt.AlignVCenter
                Repeater {
                    model: 5
                    ThemedIcon {
                        source: "../img/icon_star.svg"
                        size: Math.round(12 * root.hudScale)
                        iconColor: index < root.hudRating ? Theme.accentLight : Theme.starInactive
                    }
                }
            }

            // ── Date taken ────────────────────────────────────────────────────
            Text {
                id: dateText
                text: controller.imageDateTaken(controller.currentIndex)
                color: Theme.textSubtle
                font.pixelSize: Math.round(12 * root.hudScale)
                visible: text.length > 0
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
