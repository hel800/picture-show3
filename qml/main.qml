// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
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
        onOpened: {
            root._wasPlaying = controller.isPlaying
            if (controller.isPlaying) controller.togglePlay()
        }
        onClosed: {
            if (root._wasPlaying) controller.togglePlay()
            stack.currentItem.forceActiveFocus()
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
            onOpenHelp: if (!controller.kioskMode) helpOverlay.open()
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
            onOpenHelp: if (!controller.kioskMode) helpOverlay.open()
        }
    }
}
