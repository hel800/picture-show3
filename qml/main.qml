// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "."

ApplicationWindow {
    id: root
    width: 1100
    height: 740
    minimumWidth: 780
    minimumHeight: 560
    visible: false   // shown from Python after geometry is set, to avoid white-flash on startup
    title: "picture show 3"
    color: Theme.bgDeep

    // Set to true by AdvancedSettingsDialog (via SettingsPage) to blur the stack
    property bool advancedOpen: false

    // ── Page stack ────────────────────────────────────────────────────────────
    StackView {
        id: stack
        anchors.fill: parent

        // Blur the stack behind any modal dialog — uses scene-graph layer, survives fullscreen
        layer.enabled: root.advancedOpen || helpOverlay.visible
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.8
            blurMax: 48
        }

        // Push is instant — SettingsPage.launchAnim handles the visual transition
        pushEnter: Transition { }
        pushExit:  Transition { }

        // Pop (exit show → settings): fade + subtle upward drift
        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { property: "y"; from: 48; to: 0;  duration: 300; easing.type: Easing.OutQuad }
            }
        }
        popExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 220 }
        }

        initialItem: settingsComp
    }

    // ── React to remote enable/port changes ───────────────────────────────────
    Connections {
        target: controller
        function onSettingsChanged() {
            remoteServer.setPort(controller.remotePort)
            if (controller.remoteEnabled)
                remoteServer.start()
            else
                remoteServer.stop()
        }
    }

    // ── Help overlay (above all pages) ───────────────────────────────────────
    property bool _wasPlaying: false
    HelpOverlay {
        id: helpOverlay
        inFullscreen: root.visibility === Window.FullScreen
        onOpened: {
            root._wasPlaying = controller.isPlaying
            if (controller.isPlaying) controller.togglePlay()
        }
        onClosed: {
            if (root._wasPlaying) controller.togglePlay()
            stack.currentItem.forceActiveFocus()
        }
    }

    // ── Quit confirmation dialog (global — settings & slideshow) ─────────────
    property bool _wasPlayingQuit: false
    Popup {
        id: quitDialog
        anchors.centerIn: Overlay.overlay
        width: 390
        height: quitDialogContent.implicitHeight + 48
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose

        background: Rectangle {
            radius: 20
            color: Theme.bgCard
            border.color: Theme.surface
            border.width: 1
        }

        Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        onOpened: {
            quitYesBtn.forceActiveFocus()
            root._wasPlayingQuit = controller.isPlaying
            if (root._wasPlayingQuit && stack.depth > 1) {
                var page = stack.currentItem
                page._suppressPlayAnim = true
                controller.togglePlay()
                page._suppressPlayAnim = false
            }
        }
        onClosed: {
            if (root._wasPlayingQuit && stack.depth > 1) {
                var page = stack.currentItem
                page._suppressPlayAnim = true
                controller.togglePlay()
                page._suppressPlayAnim = false
            }
            root._wasPlayingQuit = false
            stack.currentItem.forceActiveFocus()
        }

        Item {
            id: quitDialogContent
            anchors.fill: parent
            focus: true
            implicitHeight: quitDialogCol.implicitHeight

            Keys.onPressed: function(event) {
                switch (event.key) {
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (quitNoBtn.activeFocus) quitDialog.close()
                    else Qt.quit()
                    break
                case Qt.Key_Y:
                    Qt.quit()
                    break
                case Qt.Key_N:
                case Qt.Key_Escape:
                    quitDialog.close()
                    break
                case Qt.Key_Tab:
                case Qt.Key_Backtab:
                case Qt.Key_Left:
                case Qt.Key_Right:
                    if (quitYesBtn.activeFocus) quitNoBtn.forceActiveFocus()
                    else quitYesBtn.forceActiveFocus()
                    break
                default:
                    break
                }
                event.accepted = true
            }

            ColumnLayout {
                id: quitDialogCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Image {
                        source: "../img/icon.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        sourceSize.width: 72
                        sourceSize.height: 72
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: qsTr("Exit Application")
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }

                        Text {
                            text: qsTr("Do you want to exit the application?")
                            color: Theme.textSecondary
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                            width: parent.width
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        id: quitYesBtn
                        Layout.fillWidth: true
                        height: 42
                        radius: 10
                        color: activeFocus ? Theme.accentPress : Theme.accent
                        border.color: activeFocus ? Theme.accentLight : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Yes")
                            color: "white"
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.quit()
                        }
                    }

                    Rectangle {
                        id: quitNoBtn
                        Layout.fillWidth: true
                        height: 42
                        radius: 10
                        color: activeFocus ? Theme.surfaceHover : Theme.surface
                        border.color: activeFocus ? Theme.accent : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("No")
                            color: Theme.textPrimary
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: quitDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Pages ─────────────────────────────────────────────────────────────────
    Component {
        id: settingsComp
        SettingsPage {
            Component.onCompleted: {
                forceActiveFocus()
                if (controller.remoteEnabled)
                    remoteServer.start()
                windowHelper.setCursorHidden(Window.visibility === Window.FullScreen)
            }
            onStartShow: {
                controller.startShow()
                remoteServer.setShowActive(true)
                windowHelper.setCursorHidden(true)
                stack.push(slideshowComp)
            }
            onOpenHelp: if (!controller.kioskMode) { helpOverlay.fromSettings = true; helpOverlay.open() }
            onOpenQuitDialog: quitDialog.open()
        }
    }

    Component {
        id: slideshowComp
        SlideshowPage {
            onExitShow: {
                if (controller.kioskMode) return
                controller.stopShow()
                remoteServer.setShowActive(false)
                var sp = stack.get(0)
                sp.hasStarted          = true
                sp._folderAtStart      = controller.folder
                sp._sortAtStart        = controller.sortOrder
                sp._minRatingAtStart   = controller.minRating
                stack.pop()
                sp.triggerSlideIn()
            }
            onOpenHelp: if (!controller.kioskMode) { helpOverlay.fromSettings = false; helpOverlay.open() }
            onOpenQuitDialog: quitDialog.open()
        }
    }
}
