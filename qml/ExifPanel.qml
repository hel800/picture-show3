// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: root

    // Set explicitly by parent before calling open() — not a reactive binding,
    // so content never changes while an animation is in flight.
    property var  exifData: []

    readonly property bool isOpen: _isOpen
    property bool _isOpen: false
    // Guards onStopped from clearing exifData when closeAnim is stopped by open()
    property bool _stoppingForReopen: false

    // Vertical offset applied via transform.  0 = panel at its anchored position
    // (above HUD).  Positive values shift it downward (behind/below the HUD).
    // We animate this property instead of y so that anchors can own the final
    // position — no runtime height measurement required.
    property real _slideOffset: Theme.animSlideOffset

    width:  Math.min(parent ? parent.width * 0.875 : 385, 385)
    height: panelContent.implicitHeight + 32   // 16 px top + 16 px bottom padding

    color: Theme.panelBg
    radius: 16
    border.color: Theme.panelBorderSubtle
    border.width: 1

    opacity: 0
    z: 11   // above HudBar (z:10), below play/pause popup (z:20)

    transform: Translate { y: root._slideOffset }

    // ── API ───────────────────────────────────────────────────────────────────
    // open()  — call AFTER setting exifData.
    //           Opacity 0 hides the panel while the layout engine processes the
    //           new content.  Both opacity and the slide offset animate together
    //           so no explicit layout measurement is ever needed.
    // close() — fades out and slides back behind the HUD simultaneously.

    function open() {
        _stoppingForReopen = true
        closeAnim.stop()
        _stoppingForReopen = false
        openAnim.stop()
        root.opacity      = 0
        root._slideOffset = Theme.animSlideOffset   // start below anchored position, invisible
        _isOpen           = true
        openAnim.start()
    }

    function close() {
        openAnim.stop()
        _isOpen = false
        closeAnim.start()
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

    // Fade out + nudge down; clear data once fully hidden
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
        onStopped: if (!root._stoppingForReopen) root.exifData = []
    }

    // ── Content ────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: panelContent
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 2

        // Header
        Column {
            Layout.fillWidth: true
            spacing: 5
            bottomPadding: 8

            ThemedIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "../img/icon_picture.svg"
                size: 22
                iconColor: Theme.textMuted
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("PICTURE DETAILS")
                color: Theme.textMuted
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 1.4
            }
        }

        // Data rows
        Repeater {
            model: root.exifData
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: modelData.label
                    color: Theme.textSubtle
                    font.pixelSize: 12
                    Layout.preferredWidth: Number(qsTr("100", "exif_label_width"))
                    elide: Text.ElideRight
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: _val.implicitHeight
                    clip: true

                    Text {
                        id: _val
                        text: modelData.value
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        width: !!modelData.scroll ? implicitWidth : parent.width
                        elide: !!modelData.scroll ? Text.ElideNone : Text.ElideRight

                        readonly property real _overflow: implicitWidth - parent.width

                        SequentialAnimation on x {
                            running: !!modelData.scroll && _val._overflow > 0
                            loops: Animation.Infinite
                            PauseAnimation  { duration: 1500 }
                            NumberAnimation { from: 0; to: -_val._overflow; duration: Math.max(1500, _val._overflow * 25); easing.type: Easing.InOutSine }
                            PauseAnimation  { duration: 1000 }
                            NumberAnimation { to: 0;              duration: Math.max(1500, _val._overflow * 25); easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        // Empty state — shown when no EXIF is embedded
        Text {
            visible: root.exifData.length === 0
            text: qsTr("No EXIF data available")
            color: Theme.textSubtle
            font.pixelSize: 12
            topPadding: 2
            bottomPadding: 2
        }

        // Thin separator above close hints
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.panelRowBg
            Layout.topMargin: 8
        }

        // Close hints — right-aligned
        Item {
            Layout.fillWidth: true
            implicitHeight: closeRow.implicitHeight + 2
            Row {
                id: closeRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "," }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("close")
                    color: Theme.textGhost
                    font.pixelSize: 10
                }
            }
        }
    }
}
