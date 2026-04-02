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

    // ── Inline caption edit state ─────────────────────────────────────────────
    property bool editing      : false
    property real _lastTabMs   : 0

    // Signals to SlideshowPage for autoplay pause/resume
    signal editStarted()
    signal editClosed()
    signal editConfirmed(string text)

    anchors.fill: parent
    z: 10

    // ── Sizing ────────────────────────────────────────────────────────────────
    // height = 8 % of parent height, width = 80 % of parent width.
    // _contentH drives all font sizes, star size and separator heights (50 % of HUD height).
    readonly property real _hudW     : parent.width  * 0.80
    readonly property real _hudH     : parent.height * 0.08
    readonly property real _contentH : Math.round(_hudH * 0.28)

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
        if (root.editing) cancelEdit()
        openAnim.stop()
        closeAnim.start()
    }

    // ── Edit API (called from SlideshowPage) ──────────────────────────────────
    function openEdit() {
        root._lastTabMs = 0
        captionEditInput.text = root.hudCaption
        root.editing = true
        captionEditInput.forceActiveFocus()
        captionEditInput.selectAll()
        root.editStarted()
    }

    function cancelEdit() {
        root.editing = false
        root.editClosed()
    }

    function confirmEdit() {
        root.editConfirmed(captionEditInput.text)
        root.editing = false
    }

    function refocusEdit() {
        captionEditInput.forceActiveFocus()
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
        border.color: root.editing ? Theme.accent : Qt.rgba(1, 1, 1, 0.25)
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }

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

            // ── Caption (display) / TextInput (edit) ──────────────────────────
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
                    width:  root.hudCaption.length > 0 ? implicitWidth : parent.width
                    elide:  Text.ElideNone
                    visible: root.hudCaption.length > 0 && !root.editing

                    readonly property real _overflow: implicitWidth - parent.width

                    SequentialAnimation on x {
                        running: captionText.visible && root.hudCaption.length > 0
                                 && captionText._overflow > 0 && !root.editing
                        loops:   Animation.Infinite
                        onRunningChanged: if (!running) captionText.x = 0
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

                TextInput {
                    id: captionEditInput
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    color: Theme.textPrimary
                    font.pixelSize: root._contentH
                    font.weight: Font.Medium
                    selectionColor: Theme.accent
                    selectedTextColor: "white"
                    clip: true
                    visible: root.editing

                    // Re-grab focus immediately if lost while editing (no mouse in fullscreen)
                    onActiveFocusChanged: if (!activeFocus && root.editing)
                        Qt.callLater(captionEditInput.forceActiveFocus)

                    Keys.onReturnPressed: root.confirmEdit()
                    Keys.onEnterPressed:  root.confirmEdit()
                    Keys.onEscapePressed: root.cancelEdit()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Tab) {
                            var now = Date.now()
                            if (now - root._lastTabMs < 600) {
                                var prevIdx = controller.currentIndex > 0
                                              ? controller.currentIndex - 1
                                              : controller.imageCount - 1
                                captionEditInput.text = controller.imageCaption(prevIdx)
                                captionEditInput.selectAll()
                                root._lastTabMs = 0
                            } else {
                                root._lastTabMs = now
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_F) {
                            // Let SlideshowPage handle fullscreen toggle
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

        // ── Key hints (inside box, anchored to bottom — no layout shift) ──────
        Row {
            anchors.horizontalCenter: hudBox.horizontalCenter
            anchors.bottom: hudBox.bottom
            anchors.bottomMargin: 8
            spacing: 6
            opacity: root.editing ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "↵" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("save"); color: Theme.textDisabled; font.pixelSize: 11 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Theme.textDisabled; font.pixelSize: 11 }
            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("cancel"); color: Theme.textDisabled; font.pixelSize: 11 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Theme.textDisabled; font.pixelSize: 11 }
            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Tab Tab" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("copy prev caption"); color: Theme.textDisabled; font.pixelSize: 11 }
        }
    }
}
