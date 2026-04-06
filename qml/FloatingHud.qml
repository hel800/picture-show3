// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    property real   hudScale          : 1.0
    property bool   hudVisible        : false
    property string hudCaption        : ""
    property int    hudRating         : 0
    property int    transitionDuration: 600

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
    property real _slideOffset: Theme.animSlideOffset
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
        root._slideOffset = Theme.animSlideOffset
        openAnim.start()
    }

    function _close() {
        if (root.editing) cancelEdit()
        contentCrossfade.stop()
        root._crossfading = false
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
        root.editing = false
        root.editConfirmed(captionEditInput.text)
    }

    function refocusEdit() {
        captionEditInput.forceActiveFocus()
    }

    // ── Buffered display values (frozen during crossfade) ────────────────────
    // Declared as plain values — no declarative bindings, so they only change
    // when explicitly assigned (in _refreshDisplay or the change handlers).
    property bool   _crossfading    : false
    property string _displayCount   : ""
    property string _displayCaption : ""
    property int    _displayRating  : 0
    property string _displayDate    : ""

    Component.onCompleted: refreshDisplay()

    // Display values are updated ONLY by:
    //   1. _refreshDisplay()       — called from SlideshowPage for non-transition updates
    //   2. ScriptAction midpoint   — called at opacity 0 during crossfade
    // No automatic handlers — prevents premature updates before crossfade starts.

    function refreshDisplay() {
        _displayCount   = (controller.currentIndex + 1) + " / " + controller.imageCount
        _displayCaption = root.hudCaption
        _displayRating  = root.hudRating
        _displayDate    = controller.imageDateTaken(controller.currentIndex)
    }

    // ── Content crossfade on image change ─────────────────────────────────────
    function crossfadeContent() {
        if (!root.hudVisible) return
        contentCrossfade.stop()
        root._crossfading = true
        contentRow.opacity = 1
        contentCrossfade.start()
    }

    SequentialAnimation {
        id: contentCrossfade
        NumberAnimation {
            target: contentRow; property: "opacity"
            to: 0; duration: root.transitionDuration / 2
            easing.type: Easing.OutQuad
        }
        ScriptAction { script: root.refreshDisplay() }
        NumberAnimation {
            target: contentRow; property: "opacity"
            to: 1; duration: root.transitionDuration / 2
            easing.type: Easing.InQuad
        }
        ScriptAction { script: root._crossfading = false }
    }

    // Fade in + nudge up with bounce
    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "opacity"
            from: 0; to: 1; duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "_slideOffset"
            from: Theme.animSlideOffset; to: 0
            duration: Theme.animSlideInDuration; easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot
        }
    }

    // Fade out + nudge down
    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "opacity"
            to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root; property: "_slideOffset"
            to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad
        }
        onStopped: if (!root._stoppingForReopen) root._slideOffset = Theme.animSlideOffset
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
            id: contentRow
            anchors {
                fill: parent
                leftMargin:  Math.round(32 * root.hudScale)
                rightMargin: Math.round(32 * root.hudScale)
            }
            spacing: Math.round(18 * root.hudScale)

            // ── Counter ───────────────────────────────────────────────────────
            Text {
                text: root._displayCount
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
                    text: root._displayCaption
                    color: Theme.textPrimary
                    font.pixelSize: root._contentH
                    font.weight: Font.Medium
                    width:  root._displayCaption.length > 0 ? implicitWidth : parent.width
                    elide:  Text.ElideNone
                    visible: root._displayCaption.length > 0 && !root.editing

                    readonly property real _overflow: implicitWidth - parent.width

                    SequentialAnimation on x {
                        running: captionText.visible && root._displayCaption.length > 0
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
                visible: root._displayRating > 0 || dateText.visible
            }

            // ── Star rating ───────────────────────────────────────────────────
            Row {
                spacing: Math.round(2 * root.hudScale)
                visible: root._displayRating > 0
                Layout.alignment: Qt.AlignVCenter
                Repeater {
                    model: 5
                    ThemedIcon {
                        source: "../img/icon_star.svg"
                        size: root._contentH
                        iconColor: index < root._displayRating ? Theme.accentLight : Theme.starInactive
                    }
                }
            }

            // ── Separator between stars and date ─────────────────────────────
            Rectangle {
                width: 1; height: root._contentH
                color: Qt.rgba(1, 1, 1, 0.2)
                Layout.alignment: Qt.AlignVCenter
                visible: root._displayRating > 0 && dateText.visible
            }

            // ── Date taken ────────────────────────────────────────────────────
            Text {
                id: dateText
                text: root._displayDate
                color: Theme.textSubtle
                font.pixelSize: root._contentH
                visible: text.length > 0
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── Key hints (inside box, anchored to bottom — no layout shift) ──────
        // Sizes are divided by the DPI scale factor so the hints stay the same
        // physical size as the HUD itself, which is screen-proportional.
        Row {
            anchors.horizontalCenter: hudBox.horizontalCenter
            anchors.bottom: hudBox.bottom
            anchors.bottomMargin: Math.round(8 * 100 / controller.uiScale)
            spacing: Math.round(6 * 100 / controller.uiScale)
            opacity: root.editing ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "↵";         uiScale: 100 / controller.uiScale }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("save");              color: Theme.textDisabled; font.pixelSize: Math.round(11 * 100 / controller.uiScale) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "·";                       color: Theme.textDisabled; font.pixelSize: Math.round(11 * 100 / controller.uiScale) }
            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc";        uiScale: 100 / controller.uiScale }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("cancel");            color: Theme.textDisabled; font.pixelSize: Math.round(11 * 100 / controller.uiScale) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "·";                       color: Theme.textDisabled; font.pixelSize: Math.round(11 * 100 / controller.uiScale) }
            KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Tab Tab";    uiScale: 100 / controller.uiScale }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("copy prev caption"); color: Theme.textDisabled; font.pixelSize: Math.round(11 * 100 / controller.uiScale) }
        }
    }
}
