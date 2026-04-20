// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// ── Z-layer stack ─────────────────────────────────────────────────────────────
//  0        layerB (background image)
//  1        layerA (foreground image)
//  2        (reserved for future image layers)
//  10       HudBar (bottom bar)
//  11       ExifPanel (above HudBar)
//  20       playPausePopup (above all panels)
//  25       noImagesOverlay (covers everything when no images are available)
//  30       jumpOverlay / ratingOverlay / captionOverlay / kioskQuitDialog (top tier)
//  50       leaveOverlay (background mode leave animation — above everything)
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root
    color: Theme.bgDeep
    focus: true
    clip: true   // keep sliding layers from painting outside the window

    signal exitShow()
    signal openHelp()
    signal openQuitDialog()
    signal leaveAnimDone()   // background mode: emitted when the leave animation finishes

    // ── Background mode leave animation ───────────────────────────────────────
    // Triggered by main.qml when /control/stop is received.
    // Sequence: image fades to dark (600 ms) → logo visible (2 000 ms) →
    //           logo shrinks + fades (1 000 ms) → leaveAnimDone emitted.
    function startLeaveAnim() {
        // Reset to initial state before (re-)starting
        leaveOverlay.opacity = 0
        leaveLogo.opacity    = 0
        leaveLogo.scale      = 1.0
        leaveOverlay.visible = true
        leaveAnim.restart()
    }

    // ── State ─────────────────────────────────────────────────────────────────
    property bool showingA  : true   // which layer is currently the foreground
    property int  navDir    : 1      // +1 forward, -1 backward (for slide direction)
    property int  transDur  : controller.transitionDuration
    property bool   hudVisible  : controller.hudVisible  // restored from settings
    property real   hudScale   : controller.hudSize / 100.0
    property string hudCaption : controller.imageCaption(controller.currentIndex)
    property int    hudRating  : controller.imageRating(controller.currentIndex)
    property string hudStyle   : controller.hudStyle
    // Height the floating HUD occupies from the bottom (HUD height + its bottom margin).
    // Zero when not in floating mode or when the HUD is hidden.
    readonly property real _floatingHudClearance:
        (root.hudStyle === "floating" && root.hudVisible)
        ? floatingHud._hudH + 40 : 0

    property bool   _exifVisible     : false
    property bool   _exiting         : false   // set on exit to suppress the play/pause popup
    property bool   _suppressPlayAnim: false   // set while quit dialog pauses/resumes silently

    // ── Interval edit state (play/pause popup in edit mode) ───────────────────
    property bool _ppEditMode      : false
    property int  _ppEditSeconds   : 5
    property int  _ppDigitCount    : 0    // 0 = no digit yet, 1 = one digit, 2 = two digits
    property bool _ppEndOfShow     : false  // true when autoplay stopped at last image

    onWidthChanged:  if (panoramaActive) _panoramaAbort()
    onHeightChanged: if (panoramaActive) _panoramaAbort()

    // ── Panorama mode state ───────────────────────────────────────────────────
    property bool panoramaActive      : false
    property bool _panoWasPlaying     : false
    property bool _panoCleanupPending : false
    property int  _pendingNav         : 0       // 0=none  1=next  -1=prev
    property var  _panoLayer          : null    // the layer currently being animated
    property real _panoScrollRange     : 0       // pre-computed at panorama start, stable even if image reloads
    property bool _pendingPanorama     : false   // P pressed during a transition — start panorama when transition finishes
    property bool _autoPanoramaActive  : false   // true while auto-panorama single-sweep is running
    property bool _autoPanoramaSkip   : false   // true after user cancels auto-panorama; reset on next image
    // When true, forces both images to PreserveAspectFit regardless of the
    // imageFill setting.  Used by fill-mode panorama so the full image width
    // is available for scrolling.  Avoids Qt.binding() closures whose
    // create/destroy cycle can cause stack overflows on repeated panoramas.
    property bool _forceFit           : false

    // ── Cursor: hidden in fullscreen via QGuiApplication override ────────────
    // MouseArea.cursorShape is applied lazily (only on pointer-enter), so on
    // Linux/RPi the cursor stays visible at (0,0) until the first mouse move.
    // windowHelper.setCursorHidden() uses QGuiApplication.setOverrideCursor,
    // which takes effect immediately and works on all platforms.
    Component.onDestruction: windowHelper.setCursorHidden(false)

    // Window.window is a QQuickWindow (not an Item) so it cannot be used as a
    // Connections target in QML. Use onVisibilityChanged directly on the Window
    // attached property instead.
    Window.onVisibilityChanged: windowHelper.setCursorHidden(Window.visibility !== Window.Windowed)

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

        Rectangle { anchors.fill: parent; color: Theme.bgDeep }   // prevents bleed-through
        Image {
            id: imgA
            anchors.fill: parent
            fillMode: (controller.imageFill && !root._forceFit) ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
            onStatusChanged: if (status === Image.Ready && root.showingA) root._tryAutoPanorama()
        }
    }

    // ── Layer B ───────────────────────────────────────────────────────────────
    Item {
        id: layerB
        width: parent.width; height: parent.height
        opacity: 0; z: 0

        Rectangle { anchors.fill: parent; color: Theme.bgDeep }
        Image {
            id: imgB
            anchors.fill: parent
            fillMode: (controller.imageFill && !root._forceFit) ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
            onStatusChanged: if (status === Image.Ready && !root.showingA) root._tryAutoPanorama()
        }
    }

    // ── Animations ────────────────────────────────────────────────────────────

    function _checkPendingPanorama() {
        if (root._pendingPanorama) { root._pendingPanorama = false; startPanorama() }
        else root._tryAutoPanorama()
    }

    // Fade
    ParallelAnimation {
        id: fadeAnim
        NumberAnimation { id: fadeInAnim;  property: "opacity"; to: 1; duration: root.transDur; easing.type: Easing.InOutQuad }
        NumberAnimation { id: fadeOutAnim; property: "opacity"; to: 0; duration: root.transDur; easing.type: Easing.InOutQuad }
        onStopped: root._checkPendingPanorama()
    }

    // Slide — zoom-out → slide → zoom-in
    SequentialAnimation {
        id: slideAnim
        // Phase 1: outgoing layer zooms out slightly
        NumberAnimation { id: slideZoomOut; property: "scale"; to: 0.90; easing.type: Easing.OutCubic }
        // Phase 2: both layers slide simultaneously
        ParallelAnimation {
            NumberAnimation { id: slideInAnim;  property: "x"; easing.type: Easing.InOutCubic }
            NumberAnimation { id: slideOutAnim; property: "x"; easing.type: Easing.InOutCubic }
        }
        // Phase 3: incoming layer zooms back to full size
        NumberAnimation { id: slideZoomIn; property: "scale"; to: 1.0; easing.type: Easing.OutCubic }
        onStopped: root._checkPendingPanorama()
    }

    // Zoom
    ParallelAnimation {
        id: zoomAnim
        NumberAnimation { id: zoomFadeIn;  property: "opacity"; to: 1;   duration: root.transDur; easing.type: Easing.OutCubic }
        NumberAnimation { id: zoomFadeOut; property: "opacity"; to: 0;   duration: root.transDur; easing.type: Easing.OutCubic }
        NumberAnimation { id: zoomScaleIn; property: "scale";   to: 1.0; duration: root.transDur; easing.type: Easing.OutCubic }
        onStopped: root._checkPendingPanorama()
    }

    // Fade to black — sequential: old image fades out, new image fades in
    SequentialAnimation {
        id: fadeBlackAnim
        NumberAnimation { id: fbOutAnim; property: "opacity"; to: 0; duration: root.transDur / 2; easing.type: Easing.InQuad }
        NumberAnimation { id: fbInAnim;  property: "opacity"; to: 1; duration: root.transDur / 2; easing.type: Easing.OutQuad }
        onStopped: root._checkPendingPanorama()
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
        onStopped: {
            if (!root.panoramaActive || root._panoCleanupPending) return
            if (root._autoPanoramaActive) {
                root._autoPanoramaActive = false
                stopPanorama()
            } else {
                root._panoramaScrollLeft()
            }
        }
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
            // In fill mode the exit animation keeps scale=s; reset it together with the
            // other properties in one synchronous block so no intermediate frame is shown.
            root.panoramaActive = false
            if (root._panoLayer) {
                root._panoLayer.layer.enabled = false
                root._panoLayer.scale = 1
                root._panoLayer.x = 0
            }
            root._panoLayer = null
            root._panoScrollRange = 0
            var wasPlaying = root._panoWasPlaying
            root._panoWasPlaying = false
            var pendingNav = root._pendingNav
            root._pendingNav = 0
            if (wasPlaying) {
                root._suppressPlayAnim = true
                controller.togglePlay()
                root._suppressPlayAnim = false
            }
            if (pendingNav === 1)       { root.navDir = 1;  controller.nextImage() }
            else if (pendingNav === -1) { root.navDir = -1; controller.prevImage() }
            root._forceFit = false
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
        if (controller.imageCount === 0) return
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
            floatingHud.refreshDisplay()
            return
        }

        floatingHud.crossfadeContent()

        inc.z = 2; out.z = 1
        var style = controller.transitionStyle

        if (style === "slide") {
            var zoomDur  = Math.round(root.transDur * 0.20)
            var slideDur = root.transDur - 2 * zoomDur

            // Incoming starts off-screen at the zoom-out scale so it slides in already small
            inc.opacity = 1; inc.x = navDir * root.width; inc.scale = 0.90
            out.opacity = 1; out.x = 0;                   out.scale = 1.0

            slideZoomOut.target   = out
            slideZoomOut.from     = 1.0
            slideZoomOut.duration = zoomDur

            slideInAnim.target    = inc
            slideInAnim.from      = navDir * root.width
            slideInAnim.to        = 0
            slideInAnim.duration  = slideDur
            slideOutAnim.target   = out
            slideOutAnim.from     = 0
            slideOutAnim.to       = -navDir * root.width
            slideOutAnim.duration = slideDur

            slideZoomIn.target    = inc
            slideZoomIn.from      = 0.90
            slideZoomIn.duration  = zoomDur

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
        function onImagesChanged() {
            // Covers kiosk-mode (show started before images available) and any
            // sort/filter completing while the show is active.  _apply_filter also
            // emits currentIndexChanged right after, so showImage may be called
            // twice in quick succession — that is harmless (stopAll/resetLayers first).
            if (controller.imageCount > 0)
                showImage(true)
        }
        function onCurrentIndexChanged() {
            // Only clear the skip flag for forward navigation (RIGHT key, autoplay, remote next).
            // Backward navigation (LEFT key) keeps it set so auto panorama is suppressed.
            // navDir is reset to 1 below so autoplay always counts as forward on the next call.
            if (root.navDir >= 0) root._autoPanoramaSkip = false
            if (root.panoramaActive) _panoramaAbort()
            if (root._exifVisible) {
                exifPanel.close()
                root._exifVisible = false
            }
            if (ratingOverlay.visible) {
                ratingDimIn.stop(); ratingDimOut.start()
                _ratingWasPlaying = false   // navigation started autoplay-resume already
            }
            if (captionOverlay.visible) {
                captionDimIn.stop(); captionDimOut.start()
                _captionWasPlaying = false  // navigation started; do not resume play
            }
            if (floatingHud.editing) {
                floatingHud.editing = false
                _captionWasPlaying = false
                root.forceActiveFocus()
            }
            root._pendingPanorama = false
            showImage(true)
            root.navDir = 1   // reset so autoplay advance always counts as forward
        }
        function onIsPlayingChanged() {
            // When autoplay is toggled on while a panorama-suitable image is already
            // displayed (e.g. Space key pressed in slideshow), trigger auto panorama.
            // Must respect _suppressPlayAnim: panorama start/exit call togglePlay()
            // with that flag set — firing _tryAutoPanorama() mid-sequence would
            // immediately start a new panorama and corrupt the autoplay state.
            if (controller.isPlaying && !root._suppressPlayAnim) root._tryAutoPanorama()
        }
        function onRatingWritten(index) {
            // Restore the binding so HUD still tracks future navigations
            if (index === controller.currentIndex) {
                root.hudRating = Qt.binding(function() { return controller.imageRating(controller.currentIndex) })
                floatingHud.refreshDisplay()
            }
        }
        function onCaptionWritten(index) {
            if (index === controller.currentIndex) {
                root.hudCaption = Qt.binding(function() { return controller.imageCaption(controller.currentIndex) })
                floatingHud.refreshDisplay()
            }
        }
    }

    // ── Keyboard control ──────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        // Floating HUD inline edit — handle Enter/Esc as fallback if TextInput
        // lost focus transiently; re-force focus for any other key so typing works
        if (floatingHud.editing) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                floatingHud.confirmEdit()
            else if (event.key === Qt.Key_Escape)
                floatingHud.cancelEdit()
            else if (event.key === Qt.Key_F)
                toggleFullscreen()
            else
                floatingHud.refocusEdit()
            event.accepted = true
            return
        }

        // Caption popup is open — TextInput handles Enter/Esc/Tab; absorb everything else
        if (captionOverlay.visible) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                confirmCaption()
            else if (event.key === Qt.Key_Escape)
                closeCaption()
            else if (event.key === Qt.Key_F)
                toggleFullscreen()
            event.accepted = true
            return
        }

        // Rating popup is open — handle its keys, absorb everything else
        if (ratingOverlay.visible) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                confirmRating()
            else if (event.key === Qt.Key_Escape)
                closeRating()
            else if (event.key === Qt.Key_F)
                toggleFullscreen()
            else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_5)
                openRating(event.key - Qt.Key_0)   // update pending rating
            event.accepted = true
            return
        }

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

        // Interval edit mode — intercepts before panorama and main switch
        if (root._ppEditMode) {
            switch (event.key) {
            case Qt.Key_Up:
                root._ppEditSeconds = Math.min(99, root._ppEditSeconds + 1)
                root._ppDigitCount = 0
                break
            case Qt.Key_Down:
                root._ppEditSeconds = Math.max(1, root._ppEditSeconds - 1)
                root._ppDigitCount = 0
                break
            case Qt.Key_0: case Qt.Key_1: case Qt.Key_2: case Qt.Key_3: case Qt.Key_4:
            case Qt.Key_5: case Qt.Key_6: case Qt.Key_7: case Qt.Key_8: case Qt.Key_9: {
                const d = event.key - Qt.Key_0
                if (root._ppDigitCount === 0 || root._ppDigitCount === 2) {
                    if (d > 0) { root._ppEditSeconds = d; root._ppDigitCount = 1 }
                } else {   // _ppDigitCount === 1: append second digit
                    root._ppEditSeconds = Math.min(99, root._ppEditSeconds * 10 + d)
                    root._ppDigitCount = 2
                }
                break
            }
            case Qt.Key_Return: case Qt.Key_Enter:
                confirmIntervalEdit()
                break
            case Qt.Key_Escape:
                cancelIntervalEdit()
                break
            case Qt.Key_F:
                toggleFullscreen()
                break
            }
            event.accepted = true
            return
        }

        // Panorama mode — limited key set; F/Space/J/F1 are absorbed
        if (root.panoramaActive) {
            switch (event.key) {
            case Qt.Key_P:
                root._autoPanoramaActive = false
                root._autoPanoramaSkip = true   // don't restart on same image
                stopPanorama()
                break
            case Qt.Key_Escape:
                // Cancel panorama and stay on current image (no auto-advance).
                root._autoPanoramaActive = false
                root._autoPanoramaSkip = true   // don't restart on same image
                root._pendingNav = 0
                stopPanorama()
                break
            case Qt.Key_Right:
                // Always allow navigating forward even during auto panorama.
                if (!root._panoCleanupPending) {
                    root._autoPanoramaActive = false
                    root._pendingNav = 1
                    stopPanorama()
                }
                break
            case Qt.Key_Left:
                // Always allow navigating backward even during auto panorama.
                if (!root._panoCleanupPending) {
                    root._autoPanoramaActive = false
                    root._pendingNav = -1
                    stopPanorama()
                }
                break
            case Qt.Key_I:
                root.hudVisible = !root.hudVisible
                controller.setHudVisible(root.hudVisible)
                break
            }
            event.accepted = true
            return
        }

        // While the play popup just appeared and autoplay started, digits 1–9 enter
        // interval edit mode instead of opening the star-rating overlay.
        if (playPauseAnim.running && controller.isPlaying
                && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            openIntervalEdit()
            root._ppEditSeconds = event.key - Qt.Key_0
            root._ppDigitCount = 1
            event.accepted = true
            return
        }

        // While the autoplay countdown popup is running, Enter dismisses it and
        // starts the interval timer immediately; Escape cancels autoplay entirely.
        if (playPauseAnim.running && controller.isPlaying) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                playPauseAnim.stop()
                ppFadeOut.restart()
                controller.restartInterval()
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Escape) {
                playPauseAnim.stop()
                root._suppressPlayAnim = true
                controller.stopShow()
                root._suppressPlayAnim = false
                ppFadeOut.restart()
                event.accepted = true
                return
            }
        }

        switch (event.key) {
        case Qt.Key_Right:
            navDir = 1
            controller.nextImage()
            break
        case Qt.Key_Left:
            navDir = -1
            root._autoPanoramaSkip = true   // don't auto-pan when going backward
            controller.prevImage()
            break
        case Qt.Key_Space:
            _closeExifIfOpen()
            controller.togglePlay()
            break
        case Qt.Key_Up:
            if (playPauseAnim.running && controller.isPlaying) {
                openIntervalEdit()
                root._ppEditSeconds = Math.min(99, root._ppEditSeconds + 1)
            }
            break
        case Qt.Key_Down:
            if (playPauseAnim.running && controller.isPlaying) {
                openIntervalEdit()
                root._ppEditSeconds = Math.max(1, root._ppEditSeconds - 1)
            }
            break
        case Qt.Key_0: case Qt.Key_1: case Qt.Key_2:
        case Qt.Key_3: case Qt.Key_4: case Qt.Key_5:
            if (!playPauseAnim.running || controller.isPlaying)
                openRating(event.key - Qt.Key_0)
            break
        case Qt.Key_C:
            if (root.hudStyle === "floating" && root.hudVisible)
                floatingHud.openEdit()
            else
                openCaption()
            break
        case Qt.Key_Q:
            root.openQuitDialog()
            break
        case Qt.Key_Escape:
            if (root._exifVisible) {
                root._exifVisible = false
                exifPanel.close()
            } else if (controller.kioskMode) {
                kioskQuitDialog.open()
            } else {
                root._exiting = true
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
            if (fadeAnim.running || slideAnim.running || zoomAnim.running || fadeBlackAnim.running)
                root._pendingPanorama = true
            else
                startPanorama()
            break
        case Qt.Key_Comma:
            if (root._exifVisible) {
                root._exifVisible = false
                exifPanel.close()
            } else {
                // Set data first so the panel pre-renders at full height,
                // then open() defers the animation by one layout tick.
                let rows = controller.imageExifInfo(controller.currentIndex)
                // When the HUD is hidden, append HUD-only fields to the panel
                if (!root.hudVisible) {
                    const rating = controller.imageRating(controller.currentIndex)
                    if (rating > 0) {
                        const stars = "★".repeat(rating) + "☆".repeat(5 - rating)
                        rows = rows.concat([{ label: qsTr("Rating"), value: stars }])
                    }
                    const dateTaken = controller.imageDateTaken(controller.currentIndex)
                    if (dateTaken.length > 0)
                        rows = rows.concat([{ label: qsTr("Date taken"), value: dateTaken }])
                    const caption = controller.imageCaption(controller.currentIndex)
                    if (caption.length > 0)
                        rows = rows.concat([{ label: qsTr("Caption"), value: caption, scroll: true }])
                }
                exifPanel.exifData = rows
                root._exifVisible = true
                exifPanel.open()
            }
            break
        case Qt.Key_F1:
            root.openHelp()
            break
        default:
            break
        }
        event.accepted = true
    }

    property bool _jumpWasPlaying: false

    // ── Caption popup state ───────────────────────────────────────────────────
    property bool _captionWasPlaying : false
    property real _lastTabMs         : 0     // timestamp of last Tab press (ms)

    // ── Rating popup state ────────────────────────────────────────────────────
    property bool _ratingWasPlaying  : false
    property int  _pendingRating     : 0
    property int  _starsRevealedCount: 0   // 0→5, driven by starRevealTimer

    Timer {
        id: starRevealTimer
        interval: 55
        repeat: true
        onTriggered: {
            if (root._starsRevealedCount < 5)
                root._starsRevealedCount++
            else
                stop()
        }
    }

    function _closeExifIfOpen() {
        if (root._exifVisible) {
            root._exifVisible = false
            exifPanel.close()
        }
    }

    function openCaption() {
        if (!controller.imageCount) return
        _closeExifIfOpen()
        _captionWasPlaying = controller.isPlaying
        if (controller.isPlaying) controller.togglePlay()
        captionInput.text = controller.imageCaption(controller.currentIndex)
        root._lastTabMs = 0
        captionOverlay.visible = true
        captionDimIn.start()
        captionCloseAnim.stop()
        captionBox._slideOffset = Theme.animSlideOffset
        captionOpenAnim.start()
        captionInput.forceActiveFocus()
        captionInput.selectAll()
    }

    function closeCaption() {
        captionDimIn.stop(); captionDimOut.start()   // visible = false fires in onStopped
        captionOpenAnim.stop(); captionCloseAnim.start()
        if (_captionWasPlaying) controller.togglePlay()
        _captionWasPlaying = false
        root.forceActiveFocus()
    }

    function confirmCaption() {
        controller.writeImageCaption(controller.currentIndex, captionInput.text)
        closeCaption()
    }

    function openRating(r) {
        if (!controller.imageCount) return
        _closeExifIfOpen()
        if (!ratingOverlay.visible) {
            _ratingWasPlaying = controller.isPlaying
            if (controller.isPlaying) controller.togglePlay()
            ratingOverlay.visible = true
            ratingDimIn.start()
            ratingCloseAnim.stop()
            ratingBox._slideOffset = Theme.animSlideOffset
            ratingOpenAnim.start()
        }
        var sameRating = ratingOverlay.visible && r === root._pendingRating
        root._pendingRating = r
        if (!sameRating) {
            root._starsRevealedCount = 0
            starRevealTimer.restart()
        }
    }

    function closeRating() {
        ratingDimIn.stop(); ratingDimOut.start()   // visible = false fires in onStopped
        ratingOpenAnim.stop(); ratingCloseAnim.start()
        if (_ratingWasPlaying) controller.togglePlay()
        _ratingWasPlaying = false
        root.forceActiveFocus()
    }

    function confirmRating() {
        controller.writeImageRating(controller.currentIndex, root._pendingRating)
        closeRating()
    }

    function openIntervalEdit() {
        if (controller.isPlaying) {
            root._suppressPlayAnim = true
            controller.togglePlay()
            root._suppressPlayAnim = false
        }
        countdownCanvas.progress = 0
        countdownCanvas.requestPaint()   // flush bright border before edit popup shows
        root._ppEditSeconds = Math.round(controller.interval / 1000)
        root._ppDigitCount = 0
        root._ppEditMode = true
        playPauseAnim.stop()
        playPausePopup.opacity = 1
    }

    function confirmIntervalEdit() {
        controller.setInterval(root._ppEditSeconds * 1000)
        root._ppEditMode = false
        root._suppressPlayAnim = true
        controller.togglePlay()   // always start autoplay on confirm
        root._suppressPlayAnim = false
        ppFadeOut.restart()
    }

    function cancelIntervalEdit() {
        root._ppEditMode = false
        ppFadeOut.restart()
    }

    function openJump() {
        _closeExifIfOpen()
        _jumpWasPlaying = controller.isPlaying
        if (controller.isPlaying) controller.togglePlay()
        jumpInput.text = (controller.currentIndex + 1).toString()
        jumpOverlay.visible = true
        dimOut.stop(); dimIn.start()
        jumpCloseAnim.stop()
        jumpBox._slideOffset = Theme.animSlideOffset
        jumpOpenAnim.start()
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
        jumpOpenAnim.stop(); jumpCloseAnim.start()
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

    // Called after each transition and after an image finishes loading.
    // Starts a single-sweep auto panorama when all conditions are met.
    function _tryAutoPanorama() {
        if (!controller.autoPanorama) return
        if (!controller.isPlaying) return
        if (root._autoPanoramaSkip) return
        if (root.panoramaActive || root._panoCleanupPending || root._autoPanoramaActive) return
        // Bail if a transition is still in progress — _checkPendingPanorama will re-try.
        if (fadeAnim.running || slideAnim.running || zoomAnim.running || fadeBlackAnim.running) return
        var img = root.showingA ? imgA : imgB
        if (img.implicitWidth <= 0 || img.implicitHeight <= 0) return
        if (img.implicitWidth / img.implicitHeight < root.width / root.height * 1.3) return
        root._autoPanoramaActive = true
        startPanorama()
        // startPanorama() resets _pendingNav to 0 and captures _panoWasPlaying.
        // Override: always advance to next image when the sweep ends.
        root._pendingNav = 1
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
        root._panoScrollRange = scrollRange
        root._panoWasPlaying = controller.isPlaying
        if (controller.isPlaying) {
            root._suppressPlayAnim = true
            controller.togglePlay()
            root._suppressPlayAnim = false
        }
        // Setting panoramaActive = true switches imgA/imgB fillMode to PreserveAspectFit
        // (via binding) so the full image width is available for the layer to render.
        root.panoramaActive = true
        root._pendingNav = 0
        root._panoCleanupPending = false
        // Render the layer into a larger FBO so the image is sampled at panorama
        // resolution rather than upscaled from a window-sized composite.
        if (controller.imageFill) {
            // Fill mode: force both images to PreserveAspectFit so the full image
            // width is rendered inside the layer FBO (PreserveAspectCrop clips the
            // sides).  The _forceFit flag is part of the declarative binding —
            // no Qt.binding() closures needed.
            root._forceFit = true
        }
        layer.layer.enabled = true
        layer.layer.smooth  = true
        layer.layer.textureSize = Qt.size(Math.min(Math.round(root.width * s), 4096),
                                          Math.min(Math.round(root.height * s), 4096))
        if (controller.imageFill) {
            // Fill mode: image already appeared zoomed — skip the enter animation.
            // Jump straight to scale=s, x=0 (centre) and begin scrolling immediately.
            layer.scale = s
            layer.x = 0
            _panoramaScrollRight()
        } else {
            panoScaleIn.target = layer; panoScaleIn.from = 1.0; panoScaleIn.to = s
            panoXLeft.target   = layer; panoXLeft.from   = 0;   panoXLeft.to   = scrollRange / 2
            panoramaEnterAnim.start()
        }
    }

    function stopPanorama() {
        if (root._panoCleanupPending) return   // already stopping — ignore rapid key repeat
        root._panoCleanupPending = true
        panoramaEnterAnim.stop()
        scrollRightAnim.stop()
        scrollLeftAnim.stop()
        var layer = root._panoLayer
        panoScaleOut.target = layer; panoScaleOut.from = layer.scale
        panoXCenter.target  = layer; panoXCenter.from  = layer.x
        // Fill mode: keep scale constant during exit so no black bars are revealed
        // as the animation progresses. The onStopped handler resets scale to 1 in
        // one synchronous block together with the layer/panoramaActive teardown.
        panoScaleOut.to = controller.imageFill ? layer.scale : 1.0
        panoramaExitAnim.start()
    }

    // _forceFit is cleared to restore normal fill-mode behaviour after panorama.
    // No _restoreFillMode() helper needed — just set root._forceFit = false.

    function _panoramaAbort() {
        root._panoCleanupPending = false
        root._autoPanoramaActive = false
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
        root._panoScrollRange = 0
        root._panoWasPlaying = false
        root._pendingNav = 0
        root._forceFit = false
    }

    function _panoramaScrollRight() {
        var layer = root._panoLayer
        var scrollRange = root._panoScrollRange
        if (!layer || !(scrollRange > 0)) return
        var dur = Math.max(1, Math.round(scrollRange / 250 * 1000))
        scrollRightAnim.target   = layer
        scrollRightAnim.from     = layer.x
        scrollRightAnim.to       = -scrollRange / 2
        scrollRightAnim.duration = dur
        scrollRightAnim.start()
    }

    function _panoramaScrollLeft() {
        var layer = root._panoLayer
        var scrollRange = root._panoScrollRange
        if (!layer || !(scrollRange > 0)) return
        var dur = Math.max(1, Math.round(scrollRange / 250 * 1000))
        scrollLeftAnim.target   = layer
        scrollLeftAnim.from     = layer.x
        scrollLeftAnim.to       = scrollRange / 2
        scrollLeftAnim.duration = dur
        scrollLeftAnim.start()
    }

    // ── No-images overlay ─────────────────────────────────────────────────────
    // Shown whenever imageCount==0 and no scan is in progress.
    // Covers the full screen so the user gets clear feedback instead of a
    // black frame — handles empty folders, aggressive filters, and background
    // mode before the first /control/start.
    Rectangle {
        id: noImagesOverlay
        anchors.fill: parent
        color: Theme.bgDeep
        z: 25

        readonly property bool _active: controller.imageCount === 0 && !controller.scanning
        visible: _active
        opacity: _active ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

        Column {
            anchors.centerIn: parent
            spacing: 20

            ThemedIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "../img/icon_picture.svg"
                size: 64
                iconColor: Theme.textDisabled
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("No images available")
                color: Theme.textPrimary
                font.pixelSize: 22
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Check the folder path or filter settings.")
                color: Theme.textSecondary
                font.pixelSize: 14
            }
        }
    }

    HudBar {
        id: hud
        hudScale      : root.hudScale
        hudVisible    : root.hudVisible && root.hudStyle === "fundamental"
        hudCaption    : root.hudCaption
        hudRating     : root.hudRating
        exifPanelOpen : root._exifVisible
    }

    FloatingHud {
        id: floatingHud
        hudScale           : root.hudScale
        hudVisible         : root.hudVisible && root.hudStyle === "floating"
        hudCaption         : root.hudCaption
        hudRating          : root.hudRating
        transitionDuration : root.transDur

        onEditStarted: {
            root._closeExifIfOpen()
            root._captionWasPlaying = controller.isPlaying
            if (controller.isPlaying) controller.togglePlay()
        }
        onEditClosed: {
            if (root._captionWasPlaying) controller.togglePlay()
            root._captionWasPlaying = false
            root.forceActiveFocus()
        }
        onEditConfirmed: function(text) {
            controller.writeImageCaption(controller.currentIndex, text)
            if (root._captionWasPlaying) controller.togglePlay()
            root._captionWasPlaying = false
            root.forceActiveFocus()
        }
    }

    ExifPanel {
        id: exifPanel
        // Anchored above the HUD — QML owns the final position, no height
        // measurement needed; the slide animation uses transform: Translate.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: root.hudStyle === "floating" ? parent.bottom : hud.top
        anchors.bottomMargin: 8 + root._floatingHudClearance
        // exifData is set explicitly in the key handler before open() is called,
        // not via a reactive binding — prevents content changing mid-animation.
    }

    // Show the play/pause popup whenever the playing state changes
    // (keyboard, remote control, or any other source).
    // Guard against the stopShow() call that fires during exit — that
    // isPlayingChanged emission must not show the popup on the settings page.
    Connections {
        target: controller
        function onIsPlayingChanged() {
            if (!root._exiting && !root._suppressPlayAnim && !root._ppEditMode
                    && !controller.takePlayAnimSuppression()) {
                // Set progress synchronously before restart() so the animation
                // always starts from the correct value (binding on `from` is
                // not reliably re-evaluated inside a ParallelAnimation group).
                countdownCanvas.progress = controller.isPlaying ? 1.0 : 0
                countdownCanvas.requestPaint()   // flush stale frame before popup appears
                playPausePopup.opacity = 0
                playPausePopup._ppSlideOffset = Theme.animSlideOffset
                playPauseAnim.restart()
                // Freeze the autoplay timer while the popup is visible so the
                // first image advance is a full interval after the popup fades,
                // not after Space was pressed. onFinished restarts it.
                if (controller.isPlaying) {
                    controller.pauseInterval()
                    root._ppEndOfShow = false   // reset when autoplay (re)starts
                }
            }
        }
        function onShowEnded() { root._ppEndOfShow = true }
    }

    // ── Play / Pause popup ────────────────────────────────────────────────────
    Item {
        id: playPausePopup
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 5 / 6 - height / 2
        // Fixed size — never changes between play / pause / edit states
        width: 300
        height: 88
        opacity: 0
        z: 20
        property real _ppSlideOffset: Theme.animSlideOffset
        transform: Translate { y: playPausePopup._ppSlideOffset }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.panelBg
            border.color: Theme.panelBorderMid
            border.width: 1

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 12

                Item {
                    implicitWidth: 56; implicitHeight: 56
                    Layout.alignment: Qt.AlignVCenter

                    ThemedIcon {
                        source: (root._ppEditMode || controller.isPlaying) ? "../img/icon_play.svg" : "../img/icon_pause.svg"
                        size: 56
                        iconColor: Theme.accentLight
                    }

                    // Countdown border: draws a partial clockwise rounded-rect path
                    // that shrinks like a retreating snake as progress goes 1→0.
                    // Explicit segment-by-segment drawing avoids setLineDash issues.
                    // A Timer (below) drives repaints instead of onProgressChanged
                    // to guarantee a fresh frame every 16 ms while the anim runs.
                    Canvas {
                        id: countdownCanvas
                        width: parent.width; height: parent.height
                        property real progress: 1.0

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            if (progress <= 0) return

                            var sc = width / 32
                            var bx = sc, by = sc
                            var bw = 30*sc, bh = 30*sc, r = 6*sc
                            var arcL = Math.PI / 2 * r
                            var side = bw - 2*r   // all four straight sides equal (square icon)
                            var rem  = progress * (4*side + 4*arcL)

                            ctx.beginPath()
                            ctx.strokeStyle = "#e2e8f0"
                            ctx.lineWidth   = 1.6 * sc
                            ctx.lineCap     = "round"
                            ctx.moveTo(bx + r, by)

                            // 1 top →
                            if (rem <= side) { ctx.lineTo(bx+r+rem, by); ctx.stroke(); return }
                            ctx.lineTo(bx+bw-r, by); rem -= side
                            // 2 top-right arc ↘
                            if (rem <= arcL) { ctx.arc(bx+bw-r, by+r, r, -Math.PI/2, -Math.PI/2+rem/r, false); ctx.stroke(); return }
                            ctx.arc(bx+bw-r, by+r, r, -Math.PI/2, 0, false); rem -= arcL
                            // 3 right ↓
                            if (rem <= side) { ctx.lineTo(bx+bw, by+r+rem); ctx.stroke(); return }
                            ctx.lineTo(bx+bw, by+bh-r); rem -= side
                            // 4 bottom-right arc ↙
                            if (rem <= arcL) { ctx.arc(bx+bw-r, by+bh-r, r, 0, rem/r, false); ctx.stroke(); return }
                            ctx.arc(bx+bw-r, by+bh-r, r, 0, Math.PI/2, false); rem -= arcL
                            // 5 bottom ←
                            if (rem <= side) { ctx.lineTo(bx+bw-r-rem, by+bh); ctx.stroke(); return }
                            ctx.lineTo(bx+r, by+bh); rem -= side
                            // 6 bottom-left arc ↖
                            if (rem <= arcL) { ctx.arc(bx+r, by+bh-r, r, Math.PI/2, Math.PI/2+rem/r, false); ctx.stroke(); return }
                            ctx.arc(bx+r, by+bh-r, r, Math.PI/2, Math.PI, false); rem -= arcL
                            // 7 left ↑
                            if (rem <= side) { ctx.lineTo(bx, by+bh-r-rem); ctx.stroke(); return }
                            ctx.lineTo(bx, by+r); rem -= side
                            // 8 top-left arc ↗
                            if (rem <= arcL) { ctx.arc(bx+r, by+r, r, Math.PI, Math.PI+rem/r, false); ctx.stroke(); return }
                            ctx.arc(bx+r, by+r, r, Math.PI, 3*Math.PI/2, false)

                            ctx.stroke()
                        }
                    }
                }

                ColumnLayout {
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    // Heading — always shown
                    Text {
                        text: qsTr("Auto play")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    // Timer value or pause state
                    Text {
                        text: root._ppEditMode
                              ? qsTr("Timer: %1 s").arg(root._ppEditSeconds)
                              : (controller.isPlaying
                                 ? qsTr("Timer: %1 s").arg(Math.round(controller.interval / 1000))
                                 : (root._ppEndOfShow ? qsTr("Last image") : qsTr("Pause")))
                        color: Theme.textSecondary
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    // Key hints row — always occupies space to keep fixed popup size.
                    // ↑↓ / 0–9 appear immediately in play mode; ↵ / Esc only after edit is entered.
                    Row {
                        spacing: 5
                        // Visible in play mode and edit mode; hidden in pause mode
                        opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        KeyHint { label: "↑↓"; anchors.verticalCenter: parent.verticalCenter }
                        KeyHint { label: "0–9"; anchors.verticalCenter: parent.verticalCenter }
                        // Confirm/cancel hints — revealed in play mode and edit mode
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·"; color: Theme.textDisabled; font.pixelSize: 11
                            opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        KeyHint {
                            label: "↵"; anchors.verticalCenter: parent.verticalCenter
                            opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("start"); color: Theme.textDisabled; font.pixelSize: 11
                            opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·"; color: Theme.textDisabled; font.pixelSize: 11
                            opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        KeyHint {
                            label: "Esc"; anchors.verticalCenter: parent.verticalCenter
                            opacity: (root._ppEditMode || controller.isPlaying) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                }
            }

        }

        SequentialAnimation {
            id: playPauseAnim
            // Phase 1: popup fades in and slides up
            ParallelAnimation {
                NumberAnimation { target: playPausePopup; property: "opacity"; from: 0; to: 1; duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: playPausePopup; property: "_ppSlideOffset"; from: Theme.animSlideOffset; to: 0; duration: Theme.animSlideInDuration; easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot }
            }
            // Phase 2 (3000 ms): popup fully visible — border depletes exactly during this window
            ParallelAnimation {
                PauseAnimation  { duration: 3000 }
                NumberAnimation { target: countdownCanvas; property: "progress"; to: 0; duration: 3000; easing.type: Easing.Linear }
            }
            // Phase 3: popup fades out and slides down
            ParallelAnimation {
                NumberAnimation { target: playPausePopup; property: "opacity"; to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic }
                NumberAnimation { target: playPausePopup; property: "_ppSlideOffset"; to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad }
            }

            // Reset the autoplay countdown so the first image advance is a full
            // interval after the popup disappears, not after Space was pressed.
            onFinished: if (controller.isPlaying) controller.restartInterval()
        }
        // Drives canvas repaints every frame while autoplay popup is live.
        // More reliable than onProgressChanged → requestPaint() which can be skipped.
        Timer {
            interval: 16; repeat: true
            running: playPauseAnim.running && controller.isPlaying
            onTriggered: countdownCanvas.requestPaint()
        }
        ParallelAnimation {
            id: ppFadeOut
            NumberAnimation { target: playPausePopup; property: "opacity"; to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic }
            NumberAnimation { target: playPausePopup; property: "_ppSlideOffset"; to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad }
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
            NumberAnimation { id: dimIn;  target: dimBg; property: "opacity"; to: 0.45; duration: Theme.animFadeInDuration;  easing.type: Easing.OutQuad }
            NumberAnimation { id: dimOut; target: dimBg; property: "opacity"; to: 0;    duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad
                onStopped: jumpOverlay.visible = false }
        }

        Rectangle {
            id: jumpBox
            width: 400
            height: jumpLayout.implicitHeight + 40
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(parent.height * 5 / 6 - height / 2,
                        parent.height - height - root._floatingHudClearance - 16)
            radius: 18
            color: Theme.panelBg
            border.color: Theme.panelBorderStrong
            border.width: 1
            opacity: 0
            property real _slideOffset: Theme.animSlideOffset
            transform: Translate { y: jumpBox._slideOffset }
            ParallelAnimation {
                id: jumpOpenAnim
                NumberAnimation { target: jumpBox; property: "opacity"; from: 0; to: 1; duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: jumpBox; property: "_slideOffset"; from: Theme.animSlideOffset; to: 0; duration: Theme.animSlideInDuration; easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot }
            }
            ParallelAnimation {
                id: jumpCloseAnim
                NumberAnimation { target: jumpBox; property: "opacity"; to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic }
                NumberAnimation { target: jumpBox; property: "_slideOffset"; to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad }
            }

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
                            color: Theme.panelDivider
                            border.color: jumpInput.acceptableInput ? Theme.panelBorderMid : Theme.statusWarn
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
                    color: Theme.panelSectionBg
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

    // ── Rate-image popup ──────────────────────────────────────────────────────
    Item {
        id: ratingOverlay
        anchors.fill: parent
        visible: false
        z: 30

        Rectangle {
            id: ratingDimBg
            anchors.fill: parent
            color: "black"
            opacity: 0
            NumberAnimation { id: ratingDimIn;  target: ratingDimBg; property: "opacity"; to: 0.45; duration: Theme.animFadeInDuration;  easing.type: Easing.OutQuad }
            NumberAnimation { id: ratingDimOut; target: ratingDimBg; property: "opacity"; to: 0;    duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad
                onStopped: ratingOverlay.visible = false }
        }

        Rectangle {
            id: ratingBox
            width: 380
            height: ratingLayout.implicitHeight + 40
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(parent.height * 5 / 6 - height / 2,
                        parent.height - height - root._floatingHudClearance - 16)
            radius: 18
            color: Theme.panelBg
            border.color: Theme.panelBorderStrong
            border.width: 1
            opacity: 0
            property real _slideOffset: Theme.animSlideOffset
            transform: Translate { y: ratingBox._slideOffset }
            ParallelAnimation {
                id: ratingOpenAnim
                NumberAnimation { target: ratingBox; property: "opacity"; from: 0; to: 1; duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: ratingBox; property: "_slideOffset"; from: Theme.animSlideOffset; to: 0; duration: Theme.animSlideInDuration; easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot }
            }
            ParallelAnimation {
                id: ratingCloseAnim
                NumberAnimation { target: ratingBox; property: "opacity"; to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic }
                NumberAnimation { target: ratingBox; property: "_slideOffset"; to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad }
            }

            ColumnLayout {
                id: ratingLayout
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 14

                // Header row: star icon + label
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    ThemedIcon {
                        source: "../img/icon_star.svg"
                        size: 44
                        iconColor: root._pendingRating > 0 ? Theme.accentLight : Theme.textMuted
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: qsTr("RATE IMAGE")
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            font.letterSpacing: 1.4
                        }

                        Text {
                            text: root._pendingRating === 0
                                  ? qsTr("Remove rating")
                                  : qsTr("%1 star(s)").arg(root._pendingRating)
                            color: Theme.textSecondary
                            font.pixelSize: 14
                        }
                    }
                }

                // Star row — 5 stars that cascade in
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: 5
                        Text {
                            required property int index
                            text: index < root._pendingRating ? "★" : "☆"
                            font.pixelSize: 32
                            color: index < root._pendingRating ? Theme.accentLight : Theme.starInactive
                            opacity: index < root._starsRevealedCount ? 1.0 : 0.0
                            transform: Translate {
                                y: index < root._starsRevealedCount ? 0 : 14
                                Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                            }
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color   { ColorAnimation  { duration: 120 } }
                        }
                    }
                }

                // Key hints
                Row {
                    spacing: 6
                    KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "↵" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("confirm"); color: Theme.textDisabled; font.pixelSize: 11 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Theme.textDisabled; font.pixelSize: 11 }
                    KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("cancel"); color: Theme.textDisabled; font.pixelSize: 11 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Theme.textDisabled; font.pixelSize: 11 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("0–5 change"); color: Theme.textDisabled; font.pixelSize: 11 }
                }
            }
        }
    }

    // ── Edit-caption popup ────────────────────────────────────────────────────
    Item {
        id: captionOverlay
        anchors.fill: parent
        visible: false
        z: 30

        Rectangle {
            id: captionDimBg
            anchors.fill: parent
            color: "black"
            opacity: 0
            NumberAnimation { id: captionDimIn;  target: captionDimBg; property: "opacity"; to: 0.45; duration: Theme.animFadeInDuration;  easing.type: Easing.OutQuad }
            NumberAnimation { id: captionDimOut; target: captionDimBg; property: "opacity"; to: 0;    duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad
                onStopped: captionOverlay.visible = false }
        }

        Rectangle {
            id: captionBox
            width: Math.min(parent.width - 40, 480)
            height: captionLayout.implicitHeight + 40
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(parent.height * 5 / 6 - height / 2,
                        parent.height - height - root._floatingHudClearance - 16)
            radius: 18
            color: Theme.panelBg
            border.color: Theme.panelBorderStrong
            border.width: 1
            opacity: 0
            property real _slideOffset: Theme.animSlideOffset
            transform: Translate { y: captionBox._slideOffset }
            ParallelAnimation {
                id: captionOpenAnim
                NumberAnimation { target: captionBox; property: "opacity"; from: 0; to: 1; duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: captionBox; property: "_slideOffset"; from: Theme.animSlideOffset; to: 0; duration: Theme.animSlideInDuration; easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot }
            }
            ParallelAnimation {
                id: captionCloseAnim
                NumberAnimation { target: captionBox; property: "opacity"; to: 0; duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic }
                NumberAnimation { target: captionBox; property: "_slideOffset"; to: Theme.animSlideOffset; duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad }
            }

            ColumnLayout {
                id: captionLayout
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 14

                // Header row: icon + label
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    ThemedIcon {
                        source: "../img/icon_picture.svg"
                        size: 36
                        iconColor: Theme.textMuted
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: qsTr("EDIT CAPTION")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // Text input field
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 8
                    color: Theme.panelDivider
                    border.color: Theme.panelBorderFaint
                    border.width: 1

                    TextInput {
                        id: captionInput
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        selectionColor: Theme.accent
                        selectedTextColor: "white"
                        clip: true

                        Keys.onReturnPressed: confirmCaption()
                        Keys.onEnterPressed:  confirmCaption()
                        Keys.onEscapePressed: closeCaption()
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Tab) {
                                var now = Date.now()
                                if (now - root._lastTabMs < 600) {
                                    // Double-tab within 600 ms: copy previous image's caption
                                    var prevIdx = controller.currentIndex > 0
                                                  ? controller.currentIndex - 1
                                                  : controller.imageCount - 1
                                    captionInput.text = controller.imageCaption(prevIdx)
                                    captionInput.selectAll()
                                    root._lastTabMs = 0   // reset so triple-tab doesn't trigger
                                } else {
                                    root._lastTabMs = now
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_F) {
                                toggleFullscreen()
                                event.accepted = true
                            }
                        }
                    }
                }

                // Key hints
                Row {
                    spacing: 6
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
    }

    // ── Kiosk quit confirmation dialog ───────────────────────────────────────
    BasePopup {
        id: kioskQuitDialog
        anchors.centerIn: parent
        width: 390
        height: kioskQuitContent.implicitHeight + 48
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose

        background: Rectangle {
            radius: 20
            color: Theme.bgCard
            border.color: Theme.surface
            border.width: 1
            transform: Translate { y: kioskQuitDialog._slideOffset }
        }

        Overlay.modal: Rectangle { color: Theme.overlayDim }

        onOpened: kioskYesBtn.forceActiveFocus()
        onClosed: root.forceActiveFocus()

        Item {
            id: kioskQuitContent
            anchors.fill: parent
            focus: true
            implicitHeight: kioskQuitCol.implicitHeight

            Keys.onPressed: function(event) {
                switch (event.key) {
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (kioskNoBtn.activeFocus) kioskQuitDialog.close()
                    else Qt.quit()
                    break
                case Qt.Key_Y:
                    Qt.quit()
                    break
                case Qt.Key_N:
                case Qt.Key_Escape:
                    kioskQuitDialog.close()
                    break
                case Qt.Key_Tab:
                case Qt.Key_Backtab:
                case Qt.Key_Left:
                case Qt.Key_Right:
                    if (kioskYesBtn.activeFocus) kioskNoBtn.forceActiveFocus()
                    else kioskYesBtn.forceActiveFocus()
                    break
                default:
                    break
                }
                event.accepted = true
            }

            ColumnLayout {
                id: kioskQuitCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Image {
                        source: "../img/icon.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                        sourceSize.width: 72; sourceSize.height: 72
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
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
                        id: kioskYesBtn
                        Layout.fillWidth: true
                        height: 42
                        radius: 10
                        color: activeFocus ? Theme.accentPress : Theme.accent
                        border.color: activeFocus ? Theme.accentLight : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        focus: true

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
                        id: kioskNoBtn
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
                            onClicked: kioskQuitDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Intro fade-in (black overlay that fades away to reveal first image) ──
    Rectangle {
        id: introOverlay
        anchors.fill: parent
        color: Theme.bgDeep
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
        // Correct cursor state: onStartShow always hides it, but on desktop in
        // windowed mode the cursor should remain visible.
        windowHelper.setCursorHidden(Window.visibility !== Window.Windowed)
        showImage(true)
        introFadeOut.start()
        root.forceActiveFocus()
    }

    // ── Background mode leave animation (z:50 — above everything) ────────────
    Rectangle {
        id: leaveOverlay
        anchors.fill: parent
        color: Theme.bgDeep
        z: 50
        visible: false
        opacity: 0

        Image {
            id: leaveLogo
            anchors.centerIn: parent
            source: "../img/logo.svg"
            fillMode: Image.PreserveAspectFit
            width: 420; height: 126
            sourceSize.width: 1000; sourceSize.height: 300
            smooth: true; mipmap: true
            opacity: 0
            scale: 1.0
        }

        SequentialAnimation {
            id: leaveAnim

            // Phase 1 (600 ms): screen fades to dark while logo fades in
            ParallelAnimation {
                NumberAnimation {
                    target: leaveOverlay; property: "opacity"
                    from: 0; to: 1; duration: 600; easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: leaveLogo; property: "opacity"
                    from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic
                }
            }

            // Phase 2 (2 000 ms): logo visible
            PauseAnimation { duration: 1000 }

            // Phase 3 (1 000 ms): logo shrinks and fades simultaneously
            ParallelAnimation {
                NumberAnimation {
                    target: leaveLogo; property: "opacity"
                    to: 0; duration: 1000; easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: leaveLogo; property: "scale"
                    to: 0.55; duration: 1000; easing.type: Easing.InCubic
                }
            }

            // Signal completion — main.qml pops the stack; Python hides the window
            ScriptAction { script: root.leaveAnimDone() }
        }
    }
}
