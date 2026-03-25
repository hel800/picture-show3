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
    property real _slideOffset: 20

    width:  Math.min(parent ? parent.width * 0.7 : 308, 308)
    height: panelContent.implicitHeight + 32   // 16 px top + 16 px bottom padding

    color: Qt.rgba(0, 0, 0, 0.82)
    radius: 16
    border.color: Qt.rgba(1, 1, 1, 0.12)
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
        root._slideOffset = 20   // start 20 px below anchored position, invisible
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
            from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "_slideOffset"
            from: 20; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2
        }
    }

    // Fade out + nudge down; clear data once fully hidden
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
        onStopped: if (!root._stoppingForReopen) root.exifData = []
    }

    // ── Content ────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: panelContent
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 2

        // Header
        Text {
            text: qsTr("EXIF INFO")
            color: Theme.textMuted
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 1.4
            bottomPadding: 6
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
                    Layout.preferredWidth: 100
                }
                Text {
                    text: modelData.value
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                    elide: Text.ElideRight
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
            color: Qt.rgba(1, 1, 1, 0.07)
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
