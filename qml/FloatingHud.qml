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
    // height = 8 % of parent height, width = 80 % of parent width.
    // _contentH drives all font sizes, star size and separator heights (50 % of HUD height).
    readonly property real _hudW     : parent.width  * 0.80
    readonly property real _hudH     : parent.height * 0.08
    readonly property real _contentH : Math.round(_hudH * 0.35)

    // Vertical offset via transform — 0 = resting position, positive = shifted downward.
    property real _slideOffset: 20
    property bool _stoppingForReopen: false

    opacity: 0

    transform: Translate { y: root._slideOffset }

    onHudVisibleChanged: hudVisible ? _open() : _close()

    function _open() {
        _stoppingForReopen = true
        closeAnim.stop()
        _stoppingForReopen = false
        openAnim.stop()
        root.opacity      = 0
        root._slideOffset = 20
        openAnim.start()
    }

    function _close() {
        openAnim.stop()
        closeAnim.start()
    }

    // Fade in + nudge up with bounce
    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "opacity"
            from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "_slideOffset"
            from: 20; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2
        }
    }

    // Fade out + nudge down
    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "opacity"
            to: 0; duration: 200; easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root; property: "_slideOffset"
            to: 20; duration: 200; easing.type: Easing.InQuad
        }
        onStopped: if (!root._stoppingForReopen) root._slideOffset = 20
    }

    // ── Box ───────────────────────────────────────────────────────────────────
    Rectangle {
        id: hudBox
        width:  root._hudW
        height: root._hudH
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(40 * root.hudScale)
        radius: 18
        color:        Qt.rgba(0, 0, 0, 0.82)
        border.color: Qt.rgba(1, 1, 1, 0.25)
        border.width: 1

        RowLayout {
            anchors {
                fill: parent
                leftMargin:  Math.round(32 * root.hudScale)
                rightMargin: Math.round(32 * root.hudScale)
            }
            spacing: Math.round(18 * root.hudScale)

            // ── Counter ───────────────────────────────────────────────────────
            Text {
                text: (controller.currentIndex + 1) + " / " + controller.imageCount
                color: Theme.textSubtle
                font.pixelSize: root._contentH
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                width: 1; height: root._contentH
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
                    font.pixelSize: root._contentH
                    font.weight: Font.Medium
                    // Use natural width when scrolling; wrap to container otherwise
                    width:  root.hudCaption.length > 0 ? implicitWidth : parent.width
                    elide:  Text.ElideNone
                    visible: root.hudCaption.length > 0

                    readonly property real _overflow: implicitWidth - parent.width

                    SequentialAnimation on x {
                        running: root.hudCaption.length > 0 && captionText._overflow > 0
                        loops:   Animation.Infinite
                        // Reset x to 0 when animation stops (caption became short/empty)
                        onRunningChanged: if (!running) captionText.x = 0
                        // Instant snap to start — fires on every (re)start and loop,
                        // ensuring x is never mispositioned when the animation begins.
                        NumberAnimation { to: 0; duration: 0 }
                        PauseAnimation  { duration: 1500 }
                        NumberAnimation {
                            from: 0; to: -captionText._overflow
                            duration: Math.max(800, captionText._overflow * 10)
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation  { duration: 1000 }
                        NumberAnimation {
                            to: 0
                            duration: Math.max(800, captionText._overflow * 10)
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            // ── Separator before meta (hidden when no meta to show) ───────────
            Rectangle {
                width: 1; height: root._contentH
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
                        size: root._contentH
                        iconColor: index < root.hudRating ? Theme.accentLight : Theme.starInactive
                    }
                }
            }

            // ── Separator between stars and date ─────────────────────────────
            Rectangle {
                width: 1; height: root._contentH
                color: Qt.rgba(1, 1, 1, 0.2)
                Layout.alignment: Qt.AlignVCenter
                visible: root.hudRating > 0 && dateText.visible
            }

            // ── Date taken ────────────────────────────────────────────────────
            Text {
                id: dateText
                text: controller.imageDateTaken(controller.currentIndex)
                color: Theme.textSubtle
                font.pixelSize: root._contentH
                visible: text.length > 0
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
