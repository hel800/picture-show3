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
import QtQuick.Controls
import QtQuick.Layouts
import "."

Rectangle {
    id: root
    color: "black"
    focus: true
    clip: true   // keep sliding layers from painting outside the window

    signal exitShow()

    // ── State ─────────────────────────────────────────────────────────────────
    property bool showingA  : true   // which layer is currently the foreground
    property int  navDir    : 1      // +1 forward, -1 backward (for slide direction)
    property int  transDur  : controller.transitionDuration
    property bool   hudVisible: controller.hudVisible  // restored from settings
    property real   hudScale  : controller.hudSize / 100.0
    property string hudCaption: controller.imageCaption(controller.currentIndex)

    // ── Cursor: permanently hidden over the slideshow ─────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        acceptedButtons: Qt.LeftButton
        onPressed: root.forceActiveFocus()
        onDoubleClicked: toggleFullscreen()
    }

    // ── Layer A ───────────────────────────────────────────────────────────────
    // NOTE: explicit width/height instead of anchors so x/scale animations work
    Item {
        id: layerA
        width: parent.width; height: parent.height
        opacity: 1; z: 1

        Rectangle { anchors.fill: parent; color: "black" }   // prevents bleed-through
        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: false
        }
    }

    // ── Layer B ───────────────────────────────────────────────────────────────
    Item {
        id: layerB
        width: parent.width; height: parent.height
        opacity: 0; z: 0

        Rectangle { anchors.fill: parent; color: "black" }
        Image {
            id: imgB
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: false
        }
    }

    // ── Animations ────────────────────────────────────────────────────────────

    // Fade
    ParallelAnimation {
        id: fadeAnim
        NumberAnimation { id: fadeInAnim;  property: "opacity"; to: 1; duration: root.transDur; easing.type: Easing.InOutQuad }
        NumberAnimation { id: fadeOutAnim; property: "opacity"; to: 0; duration: root.transDur; easing.type: Easing.InOutQuad }
    }

    // Slide
    ParallelAnimation {
        id: slideAnim
        NumberAnimation { id: slideInAnim;  property: "x"; duration: root.transDur; easing.type: Easing.InOutCubic }
        NumberAnimation { id: slideOutAnim; property: "x"; duration: root.transDur; easing.type: Easing.InOutCubic }
    }

    // Zoom
    ParallelAnimation {
        id: zoomAnim
        NumberAnimation { id: zoomFadeIn;  property: "opacity"; to: 1;   duration: root.transDur; easing.type: Easing.OutCubic }
        NumberAnimation { id: zoomFadeOut; property: "opacity"; to: 0;   duration: root.transDur; easing.type: Easing.OutCubic }
        NumberAnimation { id: zoomScaleIn; property: "scale";   to: 1.0; duration: root.transDur; easing.type: Easing.OutCubic }
    }

    // Fade to black — sequential: old image fades out, new image fades in
    SequentialAnimation {
        id: fadeBlackAnim
        NumberAnimation { id: fbOutAnim; property: "opacity"; to: 0; duration: root.transDur / 2; easing.type: Easing.InQuad }
        NumberAnimation { id: fbInAnim;  property: "opacity"; to: 1; duration: root.transDur / 2; easing.type: Easing.OutQuad }
    }

    // ── Transition logic ──────────────────────────────────────────────────────
    function stopAll() {
        fadeAnim.stop(); slideAnim.stop(); zoomAnim.stop(); fadeBlackAnim.stop()
    }

    function resetLayers() {
        // Snap layers to their settled state in case animation was interrupted
        if (showingA) {
            layerA.opacity = 1; layerA.x = 0; layerA.scale = 1; layerA.z = 1
            layerB.opacity = 0; layerB.x = 0; layerB.scale = 1; layerB.z = 0
        } else {
            layerB.opacity = 1; layerB.x = 0; layerB.scale = 1; layerB.z = 1
            layerA.opacity = 0; layerA.x = 0; layerA.scale = 1; layerA.z = 0
        }
    }

    function showImage(withTransition) {
        stopAll()
        resetLayers()

        // incoming = the hidden layer, outgoing = the visible one
        var out    = showingA ? layerA : layerB
        var inc    = showingA ? layerB : layerA
        var incImg = showingA ? imgB   : imgA

        incImg.source = "image://slides/" + controller.currentIndex + "?t=" + Date.now()

        if (!withTransition) {
            inc.opacity = 1; inc.x = 0; inc.scale = 1; inc.z = 2
            out.opacity = 0; out.x = 0; out.scale = 1; out.z = 1
            showingA = !showingA
            return
        }

        inc.z = 2; out.z = 1
        var style = controller.transitionStyle

        if (style === "slide") {
            inc.opacity = 1; inc.x = navDir * root.width; inc.scale = 1
            out.opacity = 1; out.x = 0;                   out.scale = 1

            slideInAnim.target  = inc
            slideInAnim.from    = navDir * root.width
            slideInAnim.to      = 0
            slideOutAnim.target = out
            slideOutAnim.from   = 0
            slideOutAnim.to     = -navDir * root.width
            slideAnim.start()

        } else if (style === "zoom") {
            inc.opacity = 0; inc.scale = 1.08; inc.x = 0
            out.opacity = 1; out.scale = 1;    out.x = 0

            zoomFadeIn.target  = inc; zoomFadeIn.from  = 0
            zoomFadeOut.target = out; zoomFadeOut.from = 1
            zoomScaleIn.target = inc; zoomScaleIn.from = 1.08
            zoomAnim.start()

        } else if (style === "fadeblack") {
            out.opacity = 1; out.x = 0; out.scale = 1
            inc.opacity = 0; inc.x = 0; inc.scale = 1

            fbOutAnim.target = out; fbOutAnim.from = 1
            fbInAnim.target  = inc; fbInAnim.from  = 0
            fadeBlackAnim.start()

        } else {
            // "fade" and any unknown value
            inc.opacity = 0; inc.x = 0; inc.scale = 1
            out.opacity = 1; out.x = 0; out.scale = 1

            fadeInAnim.target  = inc; fadeInAnim.from  = 0
            fadeOutAnim.target = out; fadeOutAnim.from = 1
            fadeAnim.start()
        }

        showingA = !showingA
    }

    // ── React to controller index changes (autoplay, remote, keyboard) ────────
    Connections {
        target: controller
        function onCurrentIndexChanged() { showImage(true) }
    }

    // ── Keyboard control ──────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Right:
            navDir = 1
            controller.nextImage()
            break
        case Qt.Key_Left:
            navDir = -1
            controller.prevImage()
            break
        case Qt.Key_Space:
            controller.togglePlay()
            playIcon.visible  = controller.isPlaying
            pauseIcon.visible = !controller.isPlaying
            playPauseAnim.restart()
            break
        case Qt.Key_Escape:
            root.exitShow()
            break
        case Qt.Key_F:
            toggleFullscreen()
            break
        case Qt.Key_I:
            root.hudVisible = !root.hudVisible
            controller.setHudVisible(root.hudVisible)
            break
        default:
            break
        }
        event.accepted = true
    }

    function toggleFullscreen() {
        var win = Window.window
        if (win.visibility === Window.FullScreen)
            win.showNormal()
        else {
            windowHelper.saveWindowed()
            win.showFullScreen()
        }
    }

    Rectangle {
        id: hud
        z: 10   // always on top of image layers (which use z 0–2)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(52 * root.hudScale)
        color: Qt.rgba(0, 0, 0, 0.65)
        opacity: 0

        state: root.hudVisible ? "shown" : "hidden"
        states: [
            State { name: "shown";  PropertyChanges { target: hud; opacity: 1 } },
            State { name: "hidden"; PropertyChanges { target: hud; opacity: 0 } }
        ]
        transitions: Transition {
            NumberAnimation { property: "opacity"; duration: 300 }
        }

        // Subtle top border line
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        RowLayout {
            anchors { fill: parent; leftMargin: Math.round(20 * root.hudScale); rightMargin: Math.round(20 * root.hudScale) }
            spacing: Math.round(6 * root.hudScale)

            // index counter
            Text {
                text: (controller.currentIndex + 1) + " / " + controller.imageCount
                color: "white"; font.pixelSize: Math.round(16 * root.hudScale); font.weight: Font.Bold
            }

            // filename
            Text { text: "≡"; color: Theme.textSubtle; font.pixelSize: Math.round(14 * root.hudScale); Layout.leftMargin: Math.round(10 * root.hudScale) }
            Text {
                text: controller.imagePath(controller.currentIndex).split(/[/\\]/).pop()
                color: Theme.textSecondary; font.pixelSize: Math.round(13 * root.hudScale)
                elide: Text.ElideMiddle
                Layout.maximumWidth: Math.round(220 * root.hudScale)
            }

            // caption — always-present filler; text shown only when available
            Text { text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * root.hudScale); visible: root.hudCaption.length > 0 }
            Text { text: "✎"; color: Theme.textSubtle; font.pixelSize: Math.round(13 * root.hudScale); visible: root.hudCaption.length > 0 }
            Item {
                Layout.fillWidth: true
                implicitHeight: captionText.implicitHeight
                Text {
                    id: captionText
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: parent.width
                    text: root.hudCaption
                    color: Theme.textSecondary; font.pixelSize: Math.round(13 * root.hudScale)
                    visible: root.hudCaption.length > 0
                    elide: Text.ElideRight
                }
            }

            // date taken (hidden when unavailable)
            Text { text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * root.hudScale); visible: dateText.visible && captionText.truncated }
            ThemedIcon { source: "../img/icon_clock.svg"; size: Math.round(13 * root.hudScale); iconColor: Theme.textSubtle; visible: dateText.visible }
            Text {
                id: dateText
                text: controller.imageDateTaken(controller.currentIndex)
                color: Theme.textSubtle; font.pixelSize: Math.round(13 * root.hudScale)
                visible: text.length > 0
            }

            // ▶/⏸ play state
            Text {
                text: controller.isPlaying ? "▶  Playing" : "⏸  Paused"
                color: Theme.textSecondary
                font.pixelSize: Math.round(13 * root.hudScale)
                visible: controller.autoplay
            }
            Text {
                text: "·"; color: Theme.textDisabled; font.pixelSize: Math.round(14 * root.hudScale)
                visible: controller.autoplay
            }

            // ⌨ keyboard hints
            KeyHint { label: "F"; uiScale: root.hudScale; Layout.leftMargin: Math.round(10 * root.hudScale) }
            Text { text: "fullscreen"; color: Theme.textDisabled; font.pixelSize: Math.round(12 * root.hudScale) }
            KeyHint { label: "I";   uiScale: root.hudScale }
            Text { text: "info";       color: Theme.textDisabled; font.pixelSize: Math.round(12 * root.hudScale) }
            KeyHint { label: "Esc"; uiScale: root.hudScale }
            Text { text: "exit";       color: Theme.textDisabled; font.pixelSize: Math.round(12 * root.hudScale) }
        }
    }

    // ── Play / Pause popup ────────────────────────────────────────────────────
    Item {
        id: playPausePopup
        anchors.centerIn: parent
        width: 120; height: 120
        opacity: 0
        z: 20

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Image {
            id: playIcon
            source: "../img/icon_play.svg"
            width: 52; height: 52
            anchors.centerIn: parent
            smooth: true
            visible: false
        }
        Image {
            id: pauseIcon
            source: "../img/icon_pause.svg"
            width: 52; height: 52
            anchors.centerIn: parent
            smooth: true
            visible: false
        }

        SequentialAnimation {
            id: playPauseAnim
            NumberAnimation { target: playPausePopup; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutQuad }
            PauseAnimation  { duration: 700 }
            NumberAnimation { target: playPausePopup; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
        }

    }

    // ── Intro fade-in (black overlay that fades away to reveal first image) ──
    Rectangle {
        id: introOverlay
        anchors.fill: parent
        color: "black"
        z: 50
        opacity: 1

        NumberAnimation {
            id: introFadeOut
            target: introOverlay
            property: "opacity"
            from: 1; to: 0
            duration: 700
            easing.type: Easing.InQuad
            onStopped: introOverlay.visible = false
        }
    }

    // ── Initialise first image ────────────────────────────────────────────────
    Component.onCompleted: {
        showImage(false)
        introFadeOut.start()
        root.forceActiveFocus()
    }
}
