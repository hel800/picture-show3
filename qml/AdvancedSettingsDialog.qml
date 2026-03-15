import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Popup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: Math.min(parent.width - 64, 520)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        radius: 20
        color: Theme.bgCard
        border.color: Theme.surface
        border.width: 1
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24

            Text {
                text: "ADVANCED SETTINGS"
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 1.4
            }

            Item { Layout.fillWidth: true }

            // Close ×
            Rectangle {
                width: 28; height: 28; radius: 8
                color: closeHover.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Theme.textMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // ── Transition Duration ───────────────────────────────────────────────
        Text {
            text: "TRANSITION"
            color: Theme.textMuted
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 1.4
            Layout.bottomMargin: 14
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10

            Text {
                text: "Duration"
                color: Theme.textPrimary
                font.pixelSize: 14
            }
            Item { Layout.fillWidth: true }
            Text {
                text: (durationSlider.value / 1000).toFixed(1) + " s"
                color: Theme.accentLight
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Slider {
            id: durationSlider
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            from: 100; to: 3000; stepSize: 100
            value: controller.transitionDuration
            onMoved: controller.setTransitionDuration(value)

            background: Rectangle {
                x: durationSlider.leftPadding
                y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                width: durationSlider.availableWidth; height: 4; radius: 2
                color: Theme.surface
                Rectangle {
                    width: durationSlider.visualPosition * parent.width
                    height: parent.height; color: Theme.accent; radius: 2
                }
            }
            handle: Rectangle {
                x: durationSlider.leftPadding + durationSlider.visualPosition * (durationSlider.availableWidth - width)
                y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                width: 22; height: 22; radius: 11
                color: Theme.accentLight
                border.color: Theme.accent; border.width: 2
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 28
            Text { text: "0.1 s"; color: Theme.textDisabled; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: "3.0 s"; color: Theme.textDisabled; font.pixelSize: 11 }
        }

        // ── HUD Size ──────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.bottomMargin: 20 }

        Text {
            text: "HUD"
            color: Theme.textMuted
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 1.4
            Layout.bottomMargin: 14
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10

            Text {
                text: "Size"
                color: Theme.textPrimary
                font.pixelSize: 14
            }
            Item { Layout.fillWidth: true }
            Text {
                text: hudSizeSlider.value + " %"
                color: Theme.accentLight
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Slider {
            id: hudSizeSlider
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            from: 50; to: 200; stepSize: 10
            value: controller.hudSize
            onMoved: controller.setHudSize(value)

            background: Rectangle {
                x: hudSizeSlider.leftPadding
                y: hudSizeSlider.topPadding + hudSizeSlider.availableHeight / 2 - height / 2
                width: hudSizeSlider.availableWidth; height: 4; radius: 2
                color: Theme.surface
                Rectangle {
                    width: hudSizeSlider.visualPosition * parent.width
                    height: parent.height; color: Theme.accent; radius: 2
                }
            }
            handle: Rectangle {
                x: hudSizeSlider.leftPadding + hudSizeSlider.visualPosition * (hudSizeSlider.availableWidth - width)
                y: hudSizeSlider.topPadding + hudSizeSlider.availableHeight / 2 - height / 2
                width: 22; height: 22; radius: 11
                color: Theme.accentLight
                border.color: Theme.accent; border.width: 2
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 28
            Text { text: "50 %"; color: Theme.textDisabled; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: "200 %"; color: Theme.textDisabled; font.pixelSize: 11 }
        }

        // ── Smartphone Remote ─────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.bottomMargin: 20 }

        Text {
            text: "SMARTPHONE REMOTE"
            color: Theme.textMuted
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 1.4
            Layout.bottomMargin: 14
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 16

            Text { text: "Enable remote control"; color: Theme.textPrimary; font.pixelSize: 14 }
            Item { Layout.fillWidth: true }
            Switch {
                id: remoteSwitch
                checked: controller.remoteEnabled
                onToggled: controller.setRemoteEnabled(checked)

                indicator: Rectangle {
                    implicitWidth: 44; implicitHeight: 24; radius: 12
                    color: remoteSwitch.checked ? Theme.accent : Theme.surface
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {
                        x: remoteSwitch.checked ? parent.width - width - 3 : 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18; radius: 9
                        color: remoteSwitch.checked ? "white" : Theme.textMuted
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 28
            opacity: controller.remoteEnabled ? 1.0 : 0.35

            Text { text: "Port"; color: Theme.textPrimary; font.pixelSize: 14 }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 90; height: 32; radius: 8
                color: Theme.surface
                border.color: portField.activeFocus ? Theme.accent : Theme.borderMuted
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 100 } }

                TextInput {
                    id: portField
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: controller.remotePort.toString()
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    enabled: controller.remoteEnabled
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1024; top: 65535 }
                    onEditingFinished: {
                        if (acceptableInput)
                            controller.setRemotePort(parseInt(text))
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.bottomMargin: 20 }

        // ── Close button ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: 10
            color: doneArea.containsMouse ? Theme.surfaceHover : Theme.surface
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "Done"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea {
                id: doneArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.close()
            }
        }
    }

    // Pad the content
    leftPadding: 28; rightPadding: 28; topPadding: 24; bottomPadding: 24
}
