// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
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
    signal openHelp()

    // ── State ─────────────────────────────────────────────────────────────────
    property bool showingA  : true   // which layer is currently the foreground
    property int  navDir    : 1      // +1 forward, -1 backward (for slide direction)
    property int  transDur  : controller.transitionDuration
    property bool   hudVisible  : controller.hudVisible  // restored from settings
    property real   hudScale   : controller.hudSize / 100.0
    property string hudCaption : controller.imageCaption(controller.currentIndex)
    property int    hudRating  : controller.imageRating(controller.currentIndex)
    property bool   _exifVisible: false

    onWidthChanged:  if (panoramaActive) _panoramaAbort()
    onHeightChanged: if (panoramaActive) _panoramaAbort()

    // ── Panorama mode state ───────────────────────────────────────────────────
    property bool panoramaActive      : false
    property bool _panoWasPlaying     : false
    property bool _panoCleanupPending : false
    property int  _pendingNav         : 0       // 0=none  1=next  -1=prev
    property var  _panoLayer          : null    // the layer currently being animated

    // ── Cursor: hidden only in fullscreen ──────────────────────────────────────
    // Delays mouse-nav actions so a double-click can cancel them and only
    // trigger fullscreen toggle (no image change).
    Timer {
        id: mouseNavTimer
        interval: 200
        property int pendingButton: Qt.NoButton
        onTriggered: {
            if (pendingButton === Qt.LeftButton)       controller.nextImage()
            else if (pendingButton === Qt.RightButton) controller.prevImage()
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Window.window && Window.window.visibility === Window.FullScreen
                     ? Qt.BlankCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.forceActiveFocus()
        onClicked: function(mouse) {
            if (!controller.mouseNavEnabled) return
            mouseNavTimer.pendingButton = mouse.button
            mouseNavTimer.restart()
        }
        onDoubleClicked: {
            mouseNavTimer.stop()   // cancel any queued navigation
            toggleFullscreen()
        }
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
            mipmap: true
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
            mipmap: true
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

    // ── Panorama animations ───────────────────────────────────────────────────
    ParallelAnimation {
        id: panoramaEnterAnim
        NumberAnimation { id: panoScaleIn; property: "scale"; duration: 1400; easing.type: Easing.InOutCubic }
        NumberAnimation { id: panoXLeft;   property: "x";    duration: 1400; easing.type: Easing.InOutCubic }
        onStopped: if (root.panoramaActive && !root._panoCleanupPending) root._panoramaScrollRight()
    }
    NumberAnimation {
        id: scrollRightAnim
        property: "x"
        easing.type: Easing.InOutSine
        onStopped: if (root.panoramaActive && !root._panoCleanupPending) root._panoramaScrollLeft()
    }
    NumberAnimation {
        id: scrollLeftAnim
        property: "x"
        easing.type: Easing.InOutSine
        onStopped: if (root.panoramaActive && !root._panoCleanupPending) root._panoramaScrollRight()
    }
    ParallelAnimation {
        id: panoramaExitAnim
        NumberAnimation { id: panoScaleOut; property: "scale"; to: 1.0; duration: 800; easing.type: Easing.OutCubic }
        NumberAnimation { id: panoXCenter;  property: "x";    to: 0.0; duration: 800; easing.type: Easing.OutCubic }
        onStopped: {
            if (!root._panoCleanupPending) return
            root._panoCleanupPending = false
            root.panoramaActive = false
            if (root._panoLayer) root._panoLayer.layer.enabled = false
            root._panoLayer = null
            var wasPlaying = root._panoWasPlaying
            root._panoWasPlaying = false
            var pendingNav = root._pendingNav
            root._pendingNav = 0
            if (wasPlaying) controller.togglePlay()
            if (pendingNav === 1)       { root.navDir = 1;  controller.nextImage() }
            else if (pendingNav === -1) { root.navDir = -1; controller.prevImage() }
        }
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
        function onCurrentIndexChanged() {
            if (root.panoramaActive) _panoramaAbort()
            if (root._exifVisible) {
                exifPanel.close()
                root._exifVisible = false
            }
            showImage(true)
        }
    }

    // ── Keyboard control ──────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        // Jump popup is open — handle Enter/Esc, absorb everything else
        if (jumpOverlay.visible) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                jumpAndClose()
            else if (event.key === Qt.Key_Escape)
                closeJump()
            else if (event.key === Qt.Key_Up)
                adjustNumber(1)
            else if (event.key === Qt.Key_Down)
                adjustNumber(-1)
            else if (event.key === Qt.Key_F)
                toggleFullscreen()
            event.accepted = true
            return
        }

        // Panorama mode — limited key set; F/Space/J/? are absorbed
        if (root.panoramaActive) {
            switch (event.key) {
            case Qt.Key_P:
            case Qt.Key_Escape:
                stopPanorama()
                break
            case Qt.Key_Right:
                if (root._pendingNav === 0) { root._pendingNav = 1;  stopPanorama() }
                break
            case Qt.Key_Left:
                if (root._pendingNav === 0) { root._pendingNav = -1; stopPanorama() }
                break
            case Qt.Key_I:
                root.hudVisible = !root.hudVisible
                controller.setHudVisible(root.hudVisible)
                break
            }
            event.accepted = true
            return
        }

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
            playPauseAnim.restart()
            break
        case Qt.Key_Escape:
            if (root._exifVisible) {
                root._exifVisible = false
                exifPanel.close()
            } else {
                root.exitShow()
            }
            break
        case Qt.Key_F:
            toggleFullscreen()
            break
        case Qt.Key_I:
            root.hudVisible = !root.hudVisible
            controller.setHudVisible(root.hudVisible)
            break
        case Qt.Key_J:
            openJump()
            break
        case Qt.Key_P:
            startPanorama()
            break
        case Qt.Key_Comma:
            if (root._exifVisible) {
                root._exifVisible = false
                exifPanel.close()
            } else {
                // Set data first so the panel pre-renders at full height,
                // then open() defers the animation by one layout tick.
                exifPanel.exifData = controller.imageExifInfo(controller.currentIndex)
                root._exifVisible = true
                exifPanel.open()
            }
            break
        case Qt.Key_Question:
            root.openHelp()
            break
        default:
            break
        }
        event.accepted = true
    }

    property bool _jumpWasPlaying: false

    function openJump() {
        _jumpWasPlaying = controller.isPlaying
        if (controller.isPlaying) controller.togglePlay()
        jumpInput.text = (controller.currentIndex + 1).toString()
        jumpOverlay.visible = true
        dimOut.stop(); dimIn.start()
        jumpInput.forceActiveFocus()
        jumpInput.selectAll()
        previewTimer.stop()
    }

    function loadPreview() {
        if (jumpInput.acceptableInput)
            previewImg.source = "image://slides/" + (parseInt(jumpInput.text) - 1) + "?t=" + Date.now()
    }

    function closeJump() {
        dimIn.stop(); dimOut.start()   // visible = false fires in onStopped
        if (_jumpWasPlaying) controller.togglePlay()
        root.forceActiveFocus()
    }

    function adjustNumber(delta) {
        var n = jumpInput.acceptableInput ? parseInt(jumpInput.text) + delta : delta > 0 ? 1 : controller.imageCount
        jumpInput.text = Math.max(1, Math.min(controller.imageCount, n)).toString()
    }

    function jumpAndClose() {
        if (!jumpInput.acceptableInput)
            return
        var newIdx = parseInt(jumpInput.text) - 1
        root.navDir = newIdx >= controller.currentIndex ? 1 : -1
        controller.goTo(newIdx)
        closeJump()
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

    function startPanorama() {
        var img = showingA ? imgA : imgB
        if (img.implicitWidth <= 0 || img.implicitHeight <= 0) return
        var imgAspect = img.implicitWidth / img.implicitHeight
        if (imgAspect < root.width / root.height * 1.3) return
        var layer = showingA ? layerA : layerB
        var s = root.height * imgAspect / root.width
        var scrollRange = root.height * imgAspect - root.width
        root._panoLayer = layer
        root._panoWasPlaying = controller.isPlaying
        if (controller.isPlaying) controller.togglePlay()
        root.panoramaActive = true
        root._pendingNav = 0
        root._panoCleanupPending = false
        // Render the layer into a larger FBO so the image is sampled at panorama
        // resolution rather than upscaled from a window-sized composite.
        layer.layer.enabled = true
        layer.layer.smooth  = true
        layer.layer.textureSize = Qt.size(Math.min(Math.round(root.width * s), 4096),
                                          Math.min(Math.round(root.height * s), 4096))
        panoScaleIn.target = layer; panoScaleIn.from = 1.0; panoScaleIn.to = s
        panoXLeft.target   = layer; panoXLeft.from   = 0;   panoXLeft.to   = scrollRange / 2
        panoramaEnterAnim.start()
    }

    function stopPanorama() {
        root._panoCleanupPending = true
        panoramaEnterAnim.stop()
        scrollRightAnim.stop()
        scrollLeftAnim.stop()
        var layer = root._panoLayer
        panoScaleOut.target = layer; panoScaleOut.from = layer.scale
        panoXCenter.target  = layer; panoXCenter.from  = layer.x
        panoramaExitAnim.start()
    }

    function _panoramaAbort() {
        root._panoCleanupPending = false
        root.panoramaActive = false      // must be first — guards onStopped from restarting scroll
        panoramaEnterAnim.stop()
        scrollRightAnim.stop()
        scrollLeftAnim.stop()
        panoramaExitAnim.stop()
        if (root._panoLayer) {
            root._panoLayer.layer.enabled = false
            root._panoLayer.scale = 1
            root._panoLayer.x = 0
            root._panoLayer = null
        }
        root._panoWasPlaying = false
        root._pendingNav = 0
    }

    function _panoramaScrollRight() {
        var layer = root._panoLayer
        var img = showingA ? imgA : imgB
        var scrollRange = root.height * (img.implicitWidth / img.implicitHeight) - root.width
        var dur = Math.max(1, Math.round(scrollRange / 250 * 1000))
        scrollRightAnim.target   = layer
        scrollRightAnim.from     = layer.x
        scrollRightAnim.to       = -scrollRange / 2
        scrollRightAnim.duration = dur
        scrollRightAnim.start()
    }

    function _panoramaScrollLeft() {
        var layer = root._panoLayer
        var img = showingA ? imgA : imgB
        var scrollRange = root.height * (img.implicitWidth / img.implicitHeight) - root.width
        var dur = Math.max(1, Math.round(scrollRange / 250 * 1000))
        scrollLeftAnim.target   = layer
        scrollLeftAnim.from     = layer.x
        scrollLeftAnim.to       = scrollRange / 2
        scrollLeftAnim.duration = dur
        scrollLeftAnim.start()
    }

    HudBar {
        id: hud
        hudScale      : root.hudScale
        hudVisible    : root.hudVisible
        hudCaption    : root.hudCaption
        hudRating     : root.hudRating
        exifPanelOpen : root._exifVisible
    }

    ExifPanel {
        id: exifPanel
        // Anchored above the HUD — QML owns the final position, no height
        // measurement needed; the slide animation uses transform: Translate.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: hud.top
        anchors.bottomMargin: 8
        // exifData is set explicitly in the key handler before open() is called,
        // not via a reactive binding — prevents content changing mid-animation.
    }

    // ── Play / Pause popup ────────────────────────────────────────────────────
    Item {
        id: playPausePopup
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 5 / 6 - height / 2
        width: ppBox.implicitWidth
        height: ppBox.implicitHeight
        opacity: 0
        z: 20

        Rectangle {
            id: ppBox
            implicitWidth: ppLayout.implicitWidth + 40
            implicitHeight: ppLayout.implicitHeight + 32
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.82)
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 1

            RowLayout {
                id: ppLayout
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 14

                ThemedIcon {
                    source: controller.isPlaying ? "../img/icon_play.svg" : "../img/icon_pause.svg"
                    size: 36
                    iconColor: Theme.accentLight
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    spacing: 4

                    Text {
                        text: qsTr("AUTOPLAY")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                    }
                    Text {
                        text: controller.isPlaying
                              ? qsTr("Play (%1 s)").arg((controller.interval / 1000).toFixed(1))
                              : qsTr("Pause")
                        color: Theme.textSecondary
                        font.pixelSize: 14
                    }
                }
            }
        }

        SequentialAnimation {
            id: playPauseAnim
            NumberAnimation { target: playPausePopup; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutQuad }
            PauseAnimation  { duration: 900 }
            NumberAnimation { target: playPausePopup; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
        }
    }

    // ── Jump-to-image popup ───────────────────────────────────────────────────
    Item {
        id: jumpOverlay
        anchors.fill: parent
        visible: false
        z: 30

        Rectangle {
            id: dimBg
            anchors.fill: parent
            color: "black"
            opacity: 0
            NumberAnimation { id: dimIn;  target: dimBg; property: "opacity"; to: 0.45; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { id: dimOut; target: dimBg; property: "opacity"; to: 0;    duration: 220; easing.type: Easing.InQuad
                onStopped: jumpOverlay.visible = false }
        }

        Rectangle {
            id: jumpBox
            width: 400
            height: jumpLayout.implicitHeight + 40
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 5 / 6 - height / 2
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.82)
            border.color: Qt.rgba(1, 1, 1, 0.4)
            border.width: 1

            RowLayout {
                id: jumpLayout
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 18

                ThemedIcon {
                    source: "../img/icon_jump.svg"
                    size: 44
                    iconColor: Theme.accentLight
                    Layout.alignment: Qt.AlignVCenter
                    transform: Translate { y: -2 }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Text {
                        text: qsTr("JUMP TO IMAGE")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.color: jumpInput.acceptableInput ? Qt.rgba(1, 1, 1, 0.22) : Theme.statusWarn
                            border.width: 1

                            TextInput {
                                id: jumpInput
                                anchors.fill: parent
                                anchors.margins: 8
                                horizontalAlignment: TextInput.AlignHCenter
                                verticalAlignment: TextInput.AlignVCenter
                                color: acceptableInput ? "white" : Theme.statusWarn
                                font.pixelSize: 20
                                font.weight: Font.Medium
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 1; top: controller.imageCount }
                                Keys.onReturnPressed: jumpAndClose()
                                Keys.onEnterPressed:  jumpAndClose()
                                Keys.onEscapePressed: closeJump()
                                Keys.onUpPressed:     adjustNumber(1)
                                Keys.onDownPressed:   adjustNumber(-1)
                                onTextChanged: {
                                    previewAnim.stop()
                                    previewContainer.opacity = 0
                                    previewContainer.scale = 1
                                    previewImg.source = ""
                                    previewTimer.stop()
                                    if (acceptableInput) previewTimer.restart()
                                }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_F) {
                                        toggleFullscreen()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_J) {
                                        closeJump()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        Text {
                            text: "/ " + controller.imageCount
                            color: Theme.textSecondary
                            font.pixelSize: 18
                        }
                    }

                    Row {
                        spacing: 6
                        KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "↵" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("go"); color: Theme.textDisabled; font.pixelSize: 11 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Theme.textDisabled; font.pixelSize: 11 }
                        KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("cancel"); color: Theme.textDisabled; font.pixelSize: 11 }
                    }
                }

                // ── Preview image ─────────────────────────────────────────
                Rectangle {
                    id: previewContainer
                    Layout.preferredWidth: 130
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    clip: true
                    opacity: 0

                    Image {
                        id: previewImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        cache: false
                        onStatusChanged: {
                            if (status === Image.Ready) {
                                previewContainer.scale = 0.78
                                previewAnim.start()
                            }
                        }
                    }

                    ParallelAnimation {
                        id: previewAnim
                        NumberAnimation { target: previewContainer; property: "opacity"; from: 0;    to: 1;   duration: 380; easing.type: Easing.OutCubic }
                        NumberAnimation { target: previewContainer; property: "scale";   from: 0.78; to: 1.0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    }

                    Timer {
                        id: previewTimer
                        interval: 1000
                        repeat: false
                        onTriggered: loadPreview()
                    }
                }
            }
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
