// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "."

Item {
    id: root
    focus: true

    // ── Inline reusable components ───────────────────────────────────────────
    property bool   hasStarted        : false
    property string _folderAtStart    : ""
    property string _sortAtStart      : ""
    property int    _minRatingAtStart : 0
    property string _updateVersion    : ""   // set when a newer GitHub release is found
    property bool   _kioskSplashDone  : false  // true once the kiosk/jump-start fade-in completes

    readonly property bool _canStart: controller.imageCount > 0 && !controller.scanning

    // Shorthand: true when the app was started with either --kiosk or a bare <dir> argument.
    readonly property bool _autoLaunch: controller.kioskMode || controller.jumpStart

    Connections {
        target: updateChecker
        function onUpdateAvailable(version) { root._updateVersion = version }
    }

    // Kiosk / jump-start: auto-launch when both scanning=false and imageCount>0 are satisfied.
    // These two conditions are set by separate signals in the pipeline
    // (_scanning=false is emitted by scanningChanged, then _apply_filter emits
    // imagesChanged which makes imageCount>0).  Both handlers run the same guard
    // so whichever fires last triggers the launch exactly once.
    Connections {
        target: controller
        function onScanningChanged() {
            if (!root._autoLaunch || !root._kioskSplashDone || !splashOverlay.visible) return
            // Background mode: keep the window hidden until Start Show is pressed.
            // onVisibleChanged (below) will trigger the launch once the window appears.
            if (controller.backgroundMode && !windowHelper.windowVisible) return
            if (!controller.scanning && controller.imageCount > 0
                    && !kioskLaunchAnim.running) {
                kioskHeartbeat.stop()
                splashScanLabel.opacity = 0
                kioskLaunchAnim.start()
            }
            // imageCount === 0 is NOT handled here: scanningChanged fires before
            // _apply_filter() updates imageCount, so 0 may just mean "not yet filtered".
            // onImagesChanged (which fires after _apply_filter) handles that case.
        }
        function onImagesChanged() {
            if (!root._autoLaunch || !root._kioskSplashDone || !splashOverlay.visible) return
            if (controller.backgroundMode && !windowHelper.windowVisible) return
            if (!controller.scanning && controller.imageCount > 0
                    && !kioskLaunchAnim.running) {
                kioskHeartbeat.stop()
                splashScanLabel.opacity = 0
                kioskLaunchAnim.start()
            } else if (!controller.scanning && controller.imageCount === 0) {
                kioskHeartbeat.stop()
                splashScanLabel.opacity = 0
                if (controller.backgroundMode) {
                    kioskLaunchAnim.start()
                } else {
                    headerLogo.opacity = 1
                    splashOverlay.visible = false
                    windowHelper.setCursorHidden(false)
                    scrollSlideIn.start()
                }
            }
        }
    }

    // Background mode: trigger the kiosk launch animation as soon as the window
    // is shown (i.e. when the user presses Start Show on the remote).
    // This fires on every hide→show transition so subsequent Start Show presses
    // also play the splash.
    Connections {
        target: windowHelper
        function onWindowVisibleChanged(visible) {
            if (!visible || !controller.backgroundMode) return
            if (!root._autoLaunch || !root._kioskSplashDone || !splashOverlay.visible) return
            if (kioskLaunchAnim.running || splashAnim.running) return
            // Replay the full splash from the beginning:
            //   500 ms pause → 1400 ms logo fade-in → heartbeat (if scanning) →
            //   zoom-out launch — identical to the kiosk startup experience.
            kioskHeartbeat.stop()
            splashScanLabel.opacity = 0
            splashLogo.scale   = 0.88  // match splashAnim initial values
            splashLogo.opacity = 0.0
            splashAnim.restart()
        }
    }

    // Reset to "Start" when the user picks a different folder, sort order, or filter after a show
    Connections {
        target: controller
        function onSettingsChanged() {
            if (root.hasStarted && (controller.folder     !== root._folderAtStart  ||
                                    controller.sortOrder  !== root._sortAtStart    ||
                                    controller.minRating  !== root._minRatingAtStart))
                root.hasStarted = false
        }
    }

    signal startShow()
    signal openHelp()
    signal openQuitDialog()

    function launchShow() {
        if (!root._canStart) return
        if (root.hasStarted)
            root.startShow()   // resume: skip fancy transition, show fades in via SlideshowPage intro
        else
            launchAnim.restart()
    }

    function triggerSlideIn() {
        splashOverlay.visible = false   // ensure overlay is gone when returning from the show
        headerLogo.opacity = 1          // may still be 0 if launched via jump-start
        windowHelper.setCursorHidden(false)
        scrollTranslate.y = 20
        scrollSlideIn.start()
    }

    // Keep the cursor hidden in fullscreen, visible in windowed — across all modes.
    // The window reaches its final visibility after Component.onCompleted (deferred),
    // so we react here rather than relying solely on the onCompleted check.
    Window.onVisibilityChanged: {
        windowHelper.setCursorHidden(Window.visibility === Window.FullScreen)
    }

    Keys.onPressed: function(event) {
        if (launchAnim.running || splashAnim.running) { event.accepted = true; return }
        if (root._autoLaunch && splashOverlay.visible) { event.accepted = true; return }
        switch (event.key) {
        case Qt.Key_F:
            var win = Window.window
            if (win.visibility === Window.FullScreen)
                win.showNormal()
            else {
                windowHelper.saveWindowed()
                win.showFullScreen()
            }
            break
        case Qt.Key_Escape:
            root.openQuitDialog()
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root._canStart)
                launchShow()
            break
        case Qt.Key_T: {
            var styles = ["fade", "slide", "zoom", "fadeblack"]
            controller.setTransitionStyle(styles[(styles.indexOf(controller.transitionStyle) + 1) % styles.length])
            break
        }
        case Qt.Key_R:
            filterPopup.opened ? filterPopup.close() : filterPopup.open()
            break
        case Qt.Key_S: {
            var orders = ["name", "date", "random"]
            controller.setSortOrder(orders[(orders.indexOf(controller.sortOrder) + 1) % orders.length])
            break
        }
        case Qt.Key_L:
            controller.setLoop(!controller.loop)
            break
        case Qt.Key_A:
            controller.setAutoplay(!controller.autoplay)
            break
        case Qt.Key_B:
            if (controller.folder.length > 0)
                folderDialog.currentFolder = "file:///" + controller.folder.replace(/\\/g, "/")
            folderDialog.open()
            break
        case Qt.Key_H:
            if (controller.folderHistory.length > 0)
                recentPopup.open()
            break
        case Qt.Key_V:
            advancedDialog.open()
            break
        case Qt.Key_F1:
            root.openHelp()
            break
        default:
            break
        }
        event.accepted = true
    }

    // ── Folder dialog ──────────────────────────────────────────────────────────
    FolderDialog {
        id: folderDialog
        title: qsTr("Select image folder")
        onAccepted: controller.loadFolder(selectedFolder.toString())
    }

    // ── Background ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgDeep }
            GradientStop { position: 1.0; color: Theme.bgGradEnd }
        }
    }

    // ── Background sun watermark ───────────────────────────────────────────────
    Image {
        id: sunWatermark
        source: "../img/logo_sun.svg"
        width: Math.min(root.width, root.height) * 0.9
        height: width
        sourceSize.width: width; sourceSize.height: height
        anchors { top: parent.top; right: parent.right
                  topMargin: -width * 0.1; rightMargin: -width * 0.35 }
        rotation: 0
        opacity: 0
        scale: 0.9
        transformOrigin: Item.Center
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    // ── Scroll area ────────────────────────────────────────────────────────────
    ScrollView {
        id: mainScrollView
        anchors.fill: parent
        contentWidth: parent.width
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        transform: Translate { id: scrollTranslate; y: 0 }

        ColumnLayout {
            id: mainCol
            width: Math.min(root.width - 32, 680)
            height: Math.max(implicitHeight, mainScrollView.height)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            // ── Header ────────────────────────────────────────────────────────
            Item { Layout.preferredHeight: 36 }

            Image {
                id: headerLogo
                source: "../img/logo.svg"
                fillMode: Image.PreserveAspectFit
                width: 420
                height: 126
                sourceSize.width: 1000
                sourceSize.height: 300
                Layout.preferredWidth: 420
                Layout.preferredHeight: 126
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                smooth: true
                mipmap: true
                opacity: 0
                transform: Translate { id: logoTranslate; y: 0 }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

            // ── Settings card ─────────────────────────────────────────────────
            Rectangle {
                id: card
                Layout.fillWidth: true
                radius: 20
                color: Theme.bgCard
                border.color: Theme.surface
                border.width: 1
                implicitHeight: cardCol.implicitHeight + 36

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: 22
                    }
                    spacing: 18

                    // ── Folder picker ─────────────────────────────────────────
                    Text {
                        text: qsTr("IMAGE FOLDER")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                    }

                    RowLayout {
                        id: folderRow
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 10
                            color: Theme.bgDeep
                            border.color: folderInput.text.length > 0 ? Theme.accentPress : Theme.borderMuted
                            border.width: 1

                            TextInput {
                                id: folderInput
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                clip: true
                                text: controller.folder
                                onTextEdited: controller.loadFolder(text)

                                Connections {
                                    target: controller
                                    function onSettingsChanged() {
                                        if (folderInput.text !== controller.folder)
                                            folderInput.text = controller.folder
                                    }
                                }

                                Text {
                                    anchors { fill: parent }
                                    verticalAlignment: Text.AlignVCenter
                                    text: qsTr("Type a path or click Browse…")
                                    color: Theme.surfaceHover
                                    font.pixelSize: 13
                                    visible: parent.text.length === 0
                                }
                            }
                        }

                        // Browse button
                        Rectangle {
                            width: 124; height: 38
                            radius: 10
                            color: browseArea.containsMouse ? Theme.surfaceHover : Theme.surface
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Browse...")
                                    color: Theme.accentLight
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "B" }
                            }
                            MouseArea {
                                id: browseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (controller.folder.length > 0)
                                        folderDialog.currentFolder = "file:///" + controller.folder.replace(/\\/g, "/")
                                    folderDialog.open()
                                }
                            }
                        }

                        // Recent folders button (only shown when history exists)
                        Rectangle {
                            id: recentBtn
                            width: 64; height: 38
                            radius: 10
                            visible: controller.folderHistory.length > 0
                            color: recentBtnArea.containsMouse ? Theme.surfaceHover : Theme.surface
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                ThemedIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../img/icon_history.svg"
                                    size: 18
                                    iconColor: Theme.accentLight
                                }
                                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "H" }
                            }
                            MouseArea {
                                id: recentBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recentPopup.open()
                            }
                        }
                    }

                    // ── Recent folders popup ───────────────────────────────────
                    BasePopup {
                        id: recentPopup
                        anchors.centerIn: Overlay.overlay
                        width: Math.min(root.width - 64, 600)
                        modal: true
                        focus: true
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        property int selectedIndex: 0

                        onOpened: {
                            selectedIndex = 0
                            recentContentItem.forceActiveFocus()
                        }
                        onClosed: root.forceActiveFocus()

                        background: Rectangle {
                            radius: 16
                            color: Theme.bgCard
                            border.color: Theme.surface
                            border.width: 1
                            transform: Translate { y: recentPopup._slideOffset }
                        }

                        Overlay.modal: Rectangle { color: Theme.overlayDimLight }

                        contentItem: Item {
                            id: recentContentItem
                            implicitHeight: Math.min(recentOuterCol.implicitHeight + 32, root.height / 2)
                            focus: true
                            transform: Translate { y: recentPopup._slideOffset }

                            Keys.onPressed: function(event) {
                                var count = controller.folderHistory.length
                                switch (event.key) {
                                case Qt.Key_Up:
                                    if (recentPopup.selectedIndex > 0) recentPopup.selectedIndex--
                                    recentFlick.ensureVisible(recentPopup.selectedIndex)
                                    event.accepted = true
                                    break
                                case Qt.Key_Down:
                                    if (recentPopup.selectedIndex < count - 1) recentPopup.selectedIndex++
                                    recentFlick.ensureVisible(recentPopup.selectedIndex)
                                    event.accepted = true
                                    break
                                case Qt.Key_Return:
                                case Qt.Key_Enter: {
                                    var path = controller.folderHistory[recentPopup.selectedIndex]
                                    folderInput.text = path
                                    recentPopup.close()
                                    Qt.callLater(function() { controller.loadFolder(path) })
                                    event.accepted = true
                                    break
                                }
                                case Qt.Key_Delete: {
                                    var delPath = controller.folderHistory[recentPopup.selectedIndex]
                                    if (recentPopup.selectedIndex >= controller.folderHistory.length - 1)
                                        recentPopup.selectedIndex = Math.max(0, recentPopup.selectedIndex - 1)
                                    controller.removeFolderHistory(delPath)
                                    event.accepted = true
                                    break
                                }
                                default:
                                    break
                                }
                            }

                            Column {
                                id: recentOuterCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                spacing: 6

                                Text {
                                    text: qsTr("Recent Folders")
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.letterSpacing: 1.4
                                    leftPadding: 4
                                    bottomPadding: 4
                                }

                                Flickable {
                                    id: recentFlick
                                    width: recentOuterCol.width
                                    height: Math.min(recentListCol.implicitHeight,
                                                     root.height / 2 - recentHeaderHeight - 32)
                                    contentHeight: recentListCol.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        policy: recentFlick.contentHeight > recentFlick.height
                                                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                        contentItem: Rectangle {
                                            implicitWidth: 4
                                            radius: 2
                                            color: Theme.textMuted
                                            opacity: 0.5
                                        }
                                    }

                                    property real recentHeaderHeight: 30 + 6 + 1 + 36 + 6 * 3  // header + divider + clear + spacing

                                    function ensureVisible(idx) {
                                        var itemY = idx * 46  // 40 height + 6 spacing
                                        var itemH = 40
                                        if (itemY < contentY)
                                            contentY = itemY
                                        else if (itemY + itemH > contentY + height)
                                            contentY = itemY + itemH - height
                                    }

                                    Column {
                                        id: recentListCol
                                        width: parent.width
                                        spacing: 6

                                        Repeater {
                                            model: controller.folderHistory

                                            delegate: Rectangle {
                                                id: recentDelegate
                                                width: recentListCol.width - 10
                                                height: 40
                                                radius: 10
                                                color: (recentPopup.selectedIndex === index)
                                                       ? Theme.accentDeep
                                                       : (rowHover.hovered ? Theme.surface : "transparent")
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                border.color: recentPopup.selectedIndex === index ? Theme.accent : "transparent"
                                                border.width: 1

                                                // Tracks hover over the entire row (including over child MouseAreas)
                                                HoverHandler { id: rowHover }

                                                Text {
                                                    anchors { left: parent.left; right: deleteBtn.left
                                                              verticalCenter: parent.verticalCenter
                                                              leftMargin: 12; rightMargin: 4 }
                                                    text: modelData
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    elide: Text.ElideLeft
                                                }

                                                // Delete button — visible on row hover
                                                Rectangle {
                                                    id: deleteBtn
                                                    anchors { right: parent.right; rightMargin: 6
                                                              verticalCenter: parent.verticalCenter }
                                                    width: 28; height: 28
                                                    radius: 6
                                                    z: 1
                                                    color: deleteArea.containsMouse ? Theme.accentPress : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 80 } }
                                                    visible: rowHover.hovered

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "×"
                                                        color: deleteArea.containsMouse ? "white" : Theme.textMuted
                                                        font.pixelSize: 16
                                                    }
                                                    MouseArea {
                                                        id: deleteArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            var path = modelData
                                                            // Clamp selected index so it doesn't go out of bounds
                                                            if (recentPopup.selectedIndex >= controller.folderHistory.length - 1)
                                                                recentPopup.selectedIndex = Math.max(0, recentPopup.selectedIndex - 1)
                                                            controller.removeFolderHistory(path)
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: recentItemArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onEntered: recentPopup.selectedIndex = index
                                                    onClicked: {
                                                        var path = modelData
                                                        folderInput.text = path
                                                        recentPopup.close()
                                                        Qt.callLater(function() { controller.loadFolder(path) })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Divider + clear
                                Rectangle { width: recentOuterCol.width; height: 1; color: Theme.surface }

                                Rectangle {
                                    width: recentOuterCol.width
                                    height: 36
                                    radius: 10
                                    color: clearArea.containsMouse ? Theme.surface : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("Clear history")
                                        color: Theme.textMuted
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: clearArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            controller.clearFolderHistory()
                                            recentPopup.close()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Image count status (left)
                        Row {
                            visible: controller.folder.length > 0
                            spacing: 0
                            Row {
                                visible: controller.scanning
                                spacing: 5
                                ThemedIcon {
                                    y: parent.height / 2 - height / 2 + 1
                                    source: "../img/icon_scan.svg"
                                    size: 13
                                    iconColor: Theme.textMuted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        var phase = controller.scanPhase
                                        var prog  = controller.scanProgress
                                        var total = controller.totalImageCount
                                        if (phase === "filter")
                                            return prog > 0 ? qsTr("Filtering by star… %1 / %2").arg(prog).arg(total)
                                                            : qsTr("Filtering by star…")
                                        if (phase === "sort")
                                            return prog > 0 ? qsTr("Sorting by date… %1 / %2").arg(prog).arg(total)
                                                            : qsTr("Sorting by date…")
                                        return qsTr("Scanning…")
                                    }
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }
                            }
                            Text {
                                visible: !controller.scanning
                                text: controller.imageCount > 0
                                      ? qsTr("✓  %1 images found").arg(controller.imageCount)
                                      : qsTr("⚠  No supported images found in this folder")
                                color: controller.imageCount > 0 ? Theme.statusOk : Theme.statusWarn
                                font.pixelSize: 12
                            }
                            Text {
                                visible: !controller.scanning && controller.imageCount < controller.totalImageCount
                                text: qsTr("  ·  filter active")
                                color: Theme.textMuted
                                font.pixelSize: 12
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Include subfolders checkbox (right)
                        MouseArea {
                            width: recursiveRow.implicitWidth
                            height: recursiveRow.implicitHeight
                            cursorShape: Qt.PointingHandCursor
                            onClicked: controller.setRecursiveSearch(!controller.recursiveSearch)

                            Row {
                                id: recursiveRow
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Include subfolders")
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 3
                                    color: controller.recursiveSearch ? Theme.accent : "transparent"
                                    border.color: controller.recursiveSearch ? Theme.accent : Theme.textMuted
                                    border.width: 1.5
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: "white"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        visible: controller.recursiveSearch
                                    }
                                }
                            }
                        }
                    }

                    // ── Start button ──────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 46
                        radius: 14
                        color: root._canStart
                               ? (startArea.pressed ? Theme.accentPress : Theme.accent)
                               : Theme.surface
                        Behavior on color { ColorAnimation { duration: 180 } }

                        Text {
                            anchors.centerIn: parent
                            text: root._canStart
                                  ? (root.hasStarted ? qsTr("▶  Resume Picture Show") : qsTr("▶  Start Picture Show"))
                                  : (controller.scanning ? qsTr("Scanning and sorting images…") : qsTr("Select a folder to continue"))
                            color: root._canStart ? "white" : Theme.textDisabled
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }

                        KeyHint {
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            label: "↵"
                            opacity: root._canStart ? 1 : 0
                        }

                        MouseArea {
                            id: startArea
                            anchors.fill: parent
                            enabled: root._canStart
                            cursorShape: root._canStart ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: launchShow()
                        }
                    }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

                    // ── Transition style ──────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: qsTr("TRANSITION")
                                color: Theme.textMuted; font.pixelSize: 11
                                font.weight: Font.Medium; font.letterSpacing: 1.4
                            }
                            Item { Layout.fillWidth: true }
                            KeyHint { label: "T" }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "fade",      label: qsTr("Fade"),       icon: "../img/icon_trans_fade.svg"      },
                                    { id: "slide",     label: qsTr("Slide"),      icon: "../img/icon_trans_slide.svg"     },
                                    { id: "zoom",      label: qsTr("Zoom"),       icon: "../img/icon_trans_zoom.svg"      },
                                    { id: "fadeblack", label: qsTr("Fade/Black"), icon: "../img/icon_trans_fadeblack.svg" }
                                ]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 50
                                    radius: 12
                                    color: controller.transitionStyle === modelData.id
                                           ? Theme.accentDeep
                                           : (transChipArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                                    border.color: controller.transitionStyle === modelData.id
                                                  ? Theme.accent : "transparent"
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        ThemedIcon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            source: modelData.icon
                                            size: 20
                                            iconColor: controller.transitionStyle === modelData.id
                                                       ? Theme.accentLight : Theme.textMuted
                                            Behavior on iconColor { ColorAnimation { duration: 150 } }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label; font.pixelSize: 11
                                            color: controller.transitionStyle === modelData.id
                                                   ? Theme.textPrimary : Theme.textMuted
                                        }
                                    }
                                    MouseArea {
                                        id: transChipArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: controller.setTransitionStyle(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

                    // ── Sort order + Filter (shared outer row for perfect heading alignment) ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Sort order column — heading + chips
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("SORT ORDER")
                                    color: Theme.textMuted; font.pixelSize: 11
                                    font.weight: Font.Medium; font.letterSpacing: 1.4
                                }
                                Item { Layout.fillWidth: true }
                                KeyHint { label: "S" }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: [
                                        { id: "name",   label: qsTr("By Name"), icon: "../img/icon_sort_name.svg"   },
                                        { id: "date",   label: qsTr("By Date"), icon: "../img/icon_sort_date.svg"   },
                                        { id: "random", label: qsTr("Random"),  icon: "../img/icon_sort_random.svg" }
                                    ]

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 50
                                        radius: 12
                                        color: controller.sortOrder === modelData.id
                                               ? Theme.accentDeep
                                               : (sortChipArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                                        border.color: controller.sortOrder === modelData.id
                                                      ? Theme.accent : "transparent"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 3
                                            ThemedIcon {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                source: modelData.icon
                                                size: 20
                                                iconColor: controller.sortOrder === modelData.id
                                                           ? Theme.accentLight : Theme.textMuted
                                                Behavior on iconColor { ColorAnimation { duration: 150 } }
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.label; font.pixelSize: 11
                                                color: controller.sortOrder === modelData.id
                                                       ? Theme.textPrimary : Theme.textMuted
                                            }
                                        }
                                        MouseArea {
                                            id: sortChipArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: controller.setSortOrder(modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        // Filter column — heading + button
                        ColumnLayout {
                            Layout.preferredWidth: 20
                            Layout.leftMargin: 20
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("FILTER")
                                    color: Theme.textMuted; font.pixelSize: 11
                                    font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Layout.fillWidth: true
                                }
                                KeyHint { label: "R" }
                            }

                            // ── Filter button ──────────────────────────────────
                            Rectangle {
                                id: filterBtn
                                Layout.fillWidth: true; height: 50
                                radius: 12
                                color: filterBtnArea.containsMouse ? Theme.surfaceHover : Theme.surface
                                border.color: (filterPopup.opened || controller.minRating > 0) ? Theme.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                ThemedIcon {
                                    anchors.centerIn: parent
                                    source: "../img/icon_filter.svg"
                                    size: 20
                                    iconColor: controller.minRating > 0 ? Theme.accentLight : Theme.textMuted
                                    Behavior on iconColor { ColorAnimation { duration: 150 } }
                                }

                                // Active-filter indicator dot
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors { top: parent.top; right: parent.right; margins: 7 }
                                    color: Theme.accent
                                    visible: controller.minRating > 0
                                }

                                MouseArea {
                                    id: filterBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: filterPopup.opened ? filterPopup.close() : filterPopup.open()
                                }

                                // ── Filter popup ──────────────────────────────
                                Popup {
                                    id: filterPopup
                                    x: filterBtn.width - width
                                    y: -height - 6
                                    width: 230
                                    padding: 14
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                                    property int highlightIndex: 0
                                    onOpened: {
                                        highlightIndex = controller.minRating
                                        popupColumn.forceActiveFocus()
                                    }

                                    Timer {
                                        id: closeTimer
                                        interval: 180
                                        onTriggered: filterPopup.close()
                                    }

                                    background: Rectangle {
                                        color: Theme.bgCard
                                        radius: 12
                                        border.color: Theme.borderMuted
                                        border.width: 1
                                    }

                                    Column {
                                        id: popupColumn
                                        width: parent.width
                                        spacing: 10
                                        focus: true

                                        Keys.onPressed: function(event) {
                                            switch (event.key) {
                                            case Qt.Key_Up:
                                                if (filterPopup.highlightIndex > 0) filterPopup.highlightIndex--
                                                event.accepted = true; break
                                            case Qt.Key_Down:
                                                if (filterPopup.highlightIndex < 5) filterPopup.highlightIndex++
                                                event.accepted = true; break
                                            case Qt.Key_Return:
                                            case Qt.Key_Enter:
                                                controller.setMinRating(filterPopup.highlightIndex)
                                                closeTimer.restart()
                                                event.accepted = true; break
                                            }
                                        }

                                        // Star rating label
                                        Text {
                                            text: qsTr("STAR RATING")
                                            color: Theme.textMuted; font.pixelSize: 10
                                            font.weight: Font.Medium; font.letterSpacing: 1.4
                                        }

                                        // Star rating options
                                        Column {
                                            width: parent.width
                                            spacing: 2

                                            Repeater {
                                                model: [
                                                    { rating: 0, label: qsTr("All")               },
                                                    { rating: 1, label: qsTr("1 star and above")  },
                                                    { rating: 2, label: qsTr("2 stars and above") },
                                                    { rating: 3, label: qsTr("3 stars and above") },
                                                    { rating: 4, label: qsTr("4 stars and above") },
                                                    { rating: 5, label: qsTr("5 stars")           }
                                                ]

                                                delegate: Rectangle {
                                                    width: parent.width; height: 32; radius: 6
                                                    color: controller.minRating === modelData.rating
                                                           ? Theme.accentDeep
                                                           : (index === filterPopup.highlightIndex || rowHover.containsMouse
                                                              ? Theme.surface : "transparent")
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                        spacing: 6

                                                        Row {
                                                            spacing: 2
                                                            visible: modelData.rating > 0
                                                            Repeater {
                                                                model: modelData.rating
                                                                ThemedIcon {
                                                                    source: "../img/icon_star.svg"
                                                                    size: 10
                                                                    iconColor: controller.minRating === modelData.rating
                                                                               ? Theme.accentLight : Theme.textMuted
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.label
                                                            font.pixelSize: 13
                                                            color: controller.minRating === modelData.rating
                                                                   ? Theme.textPrimary : Theme.textSecondary
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: rowHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            controller.setMinRating(modelData.rating)
                                                            filterPopup.close()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

                    // ── Loop & Autoplay toggles ───────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // Loop
                        Rectangle {
                            Layout.fillWidth: true
                            height: 54
                            radius: 12
                            color: Theme.surface

                            RowLayout {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }

                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Loop"); color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { text: qsTr("Repeat after last photo"); color: Theme.textMuted; font.pixelSize: 11 }
                                }

                                Item { Layout.fillWidth: true }

                                KeyHint { label: "L" }

                                // Custom toggle switch
                                Rectangle {
                                    width: 44; height: 24; radius: 12
                                    color: controller.loop ? Theme.accent : Theme.surfaceHover
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Rectangle {
                                        width: 18; height: 18; radius: 9
                                        color: controller.loop ? "white" : Theme.textMuted
                                        x: controller.loop ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: controller.setLoop(!controller.loop)
                                    }
                                }
                            }
                        }

                        // Autoplay
                        Rectangle {
                            Layout.fillWidth: true
                            height: 54
                            radius: 12
                            color: Theme.surface

                            RowLayout {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }

                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Autoplay"); color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { text: qsTr("Advance automatically"); color: Theme.textMuted; font.pixelSize: 11 }
                                }

                                Item { Layout.fillWidth: true }

                                KeyHint { label: "A" }

                                Rectangle {
                                    width: 44; height: 24; radius: 12
                                    color: controller.autoplay ? Theme.accent : Theme.surfaceHover
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Rectangle {
                                        width: 18; height: 18; radius: 9
                                        color: controller.autoplay ? "white" : Theme.textMuted
                                        x: controller.autoplay ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: controller.setAutoplay(!controller.autoplay)
                                    }
                                }
                            }
                        }
                    }

                    // ── Interval slider (visible only when autoplay is on) ─────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: controller.autoplay
                        spacing: 10
                        opacity: controller.autoplay ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Interval"); color: Theme.textSecondary; font.pixelSize: 13 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(intervalSlider.value / 1000) + " s"
                                color: Theme.accentLight; font.pixelSize: 13; font.weight: Font.Medium
                            }
                        }

                        Slider {
                            id: intervalSlider
                            Layout.fillWidth: true
                            from: 1000; to: 99000; stepSize: 1000
                            value: controller.interval || 5000
                            onMoved: controller.setInterval(value)

                            background: Rectangle {
                                x: intervalSlider.leftPadding
                                y: intervalSlider.topPadding + intervalSlider.availableHeight / 2 - height / 2
                                width: intervalSlider.availableWidth; height: 4; radius: 2
                                color: Theme.surface
                                Rectangle {
                                    width: intervalSlider.visualPosition * parent.width
                                    height: parent.height; color: Theme.accent; radius: 2
                                }
                            }
                            handle: Rectangle {
                                x: intervalSlider.leftPadding + intervalSlider.visualPosition * (intervalSlider.availableWidth - width)
                                y: intervalSlider.topPadding + intervalSlider.availableHeight / 2 - height / 2
                                width: 22; height: 22; radius: 11
                                color: Theme.accentLight
                                border.color: Theme.accent; border.width: 2
                            }
                        }
                    }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; visible: controller.remoteEnabled }

                    // ── Remote info ───────────────────────────────────────────
                    RowLayout {
                        visible: controller.remoteEnabled
                        Layout.fillWidth: true
                        spacing: 14

                        ThemedIcon { source: "../img/icon_remote.svg"; size: 32; iconColor: Theme.accentLight }

                        Column {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: qsTr("Smartphone Remote"); color: Theme.textPrimary; font.pixelSize: 13; font.weight: Font.Medium }
                            Text {
                                text: qsTr("Open %1 on your phone during the show").arg(remoteServer.url)
                                color: Theme.textMuted; font.pixelSize: 12
                            }
                        }

                        // QR code button
                        Rectangle {
                            width: 38; height: 38
                            radius: 10
                            color: qrBtnArea.containsMouse ? Theme.surfaceHover : Theme.surface
                            Behavior on color { ColorAnimation { duration: 120 } }

                            // Mini QR icon drawn with three corner squares
                            Item {
                                anchors.centerIn: parent
                                width: 22; height: 22

                                Repeater {
                                    model: [
                                        { x: 0,  y: 0  },
                                        { x: 14, y: 0  },
                                        { x: 0,  y: 14 }
                                    ]
                                    Rectangle {
                                        x: modelData.x; y: modelData.y
                                        width: 8; height: 8; radius: 1
                                        color: Theme.accentLight
                                        Rectangle {
                                            anchors { fill: parent; margins: 2 }
                                            radius: 0
                                            color: Theme.bgCard
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 2; height: 2
                                                color: Theme.accentLight
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: 14; y: 14; width: 8; height: 8; radius: 1
                                    color: Theme.accentLight
                                }
                            }

                            MouseArea {
                                id: qrBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: qrDialog.open()
                            }
                        }
                    }

                    QrCodeDialog { id: qrDialog }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

                    // ── Advanced settings link + Help link ────────────────────
                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            height: 32; radius: 8
                            width: helpRow.implicitWidth + 24
                            color: helpArea.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: helpRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Help")
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }
                                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "F1" }
                            }
                            MouseArea {
                                id: helpArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openHelp()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Update available badge — centered between Help and Advanced settings
                        Rectangle {
                            visible: root._updateVersion !== ""
                            height: 26; radius: 8
                            width: updateBadgeRow.implicitWidth + 20
                            color: updateBadgeHover.containsMouse ? Theme.accentDeep : Theme.surface
                            border.color: Theme.accent; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                id: updateBadgeRow
                                anchors.centerIn: parent; spacing: 5
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "✦ " + qsTr("Update available:") + " v" + root._updateVersion
                                    color: Theme.accentLight; font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                id: updateBadgeHover
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://github.com/hel800/picture-show3/releases/latest")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 32; radius: 8
                            width: advancedRow.implicitWidth + 24
                            color: advancedArea.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: advancedRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Advanced settings ›")
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }
                                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "V" }
                            }
                            MouseArea {
                                id: advancedArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: advancedDialog.open()
                            }
                        }
                    }

                } // end cardCol
            } // end card

            AdvancedSettingsDialog { id: advancedDialog }

            // ── Keyboard hint ─────────────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Slideshow commands:")
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "←" }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "→" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Navigate")
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Space" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Play/Pause")
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "F" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Fullscreen")
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "Esc" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Exit")
                    color: Theme.textGhost
                    font.pixelSize: 11
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
                text: "v" + appVersion
                color: Theme.surfaceHover
                font.pixelSize: 11
                font.letterSpacing: 0.3
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 36 }
        }
    }

    // ── Welcome splash overlay ──────────────────────────────────────────────
    Rectangle {
        id: splashOverlay
        anchors.fill: parent
        z: 100
        visible: true

        // Block all mouse interaction with the settings page beneath while the
        // splash (or kiosk/jump-start heartbeat) is visible.
        MouseArea { anchors.fill: parent; hoverEnabled: true }

        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgDeep }
            GradientStop { position: 1.0; color: Theme.bgGradEnd }
        }

        Image {
            id: splashLogo
            source: "../img/logo.svg"
            fillMode: Image.PreserveAspectFit
            width: 420
            height: 126
            sourceSize.width: 1000
            sourceSize.height: 300
            x: parent.width / 2 - width / 2
            y: parent.height / 2 - height / 2
            smooth: true
            mipmap: true
            opacity: 0
            scale: 0.88
        }

        Text {
            id: splashScanLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: splashLogo.y + splashLogo.height + 24
            text: qsTr("Scanning…")
            color: Theme.textSecondary
            font.pixelSize: 14
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }

        SequentialAnimation {
            id: splashAnim
            running: true

            // Wait for window to settle
            PauseAnimation { duration: 500 }

            // Logo gently fades in and breathes to full size
            ParallelAnimation {
                NumberAnimation {
                    target: splashLogo; property: "opacity"
                    from: 0; to: 1
                    duration: 1400; easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: splashLogo; property: "scale"
                    from: 0.88; to: 1.0
                    duration: 1400; easing.type: Easing.OutCubic
                }
            }

            // Auto-launch modes (kiosk / jump-start): logo stays centred (instant).
            // Normal mode: logo drifts to header position.
            NumberAnimation {
                target: splashLogo; property: "y"
                to: root._autoLaunch ? (root.height / 2 - splashLogo.height / 2) : 36
                duration: root._autoLaunch ? 1 : 500
                easing.type: Easing.InOutCubic
            }

            // Branch: start auto-launch heartbeat, or reveal settings page
            ScriptAction {
                script: {
                    if (root._autoLaunch) {
                        root._kioskSplashDone = true
                        if (controller.backgroundMode && !windowHelper.windowVisible) {
                            // Window is hidden — launch is deferred until the window
                            // is shown (handled by Connections on Window.window above).
                            // Start heartbeat only while scan is still in progress.
                            if (controller.scanning) {
                                splashScanLabel.opacity = 0.8
                                kioskHeartbeat.start()
                            }
                        // If scan finished before the splash did, skip heartbeat
                        } else if (!controller.scanning && controller.imageCount > 0)
                            kioskLaunchAnim.start()
                        else if (!controller.scanning && controller.imageCount === 0) {
                            if (controller.backgroundMode) {
                                kioskLaunchAnim.start()
                            } else {
                                // Scan already done, no images — fall back to settings page
                                headerLogo.opacity = 1
                                splashOverlay.visible = false
                                windowHelper.setCursorHidden(false)
                                scrollSlideIn.start()
                            }
                        } else {
                            splashScanLabel.opacity = 0.8
                            kioskHeartbeat.start()
                        }
                    } else {
                        headerLogo.opacity = 1
                        splashOverlay.visible = false
                        windowHelper.setCursorHidden(false)
                        scrollSlideIn.start()
                    }
                }
            }
        }

    }
    // Slide the scroll content up after the splash (and after returning from show)
    ParallelAnimation {
        id: scrollSlideIn
        // Scroll content drifts up
        NumberAnimation { target: scrollTranslate; property: "y"; from: 40; to: 0; duration: 350; easing.type: Easing.OutQuad }
        // Logo counter-translates so it stays visually fixed
        NumberAnimation { target: logoTranslate;   property: "y"; from: -40; to: 0; duration: 350; easing.type: Easing.OutQuad }
        // Sun watermark fades and zooms in
        NumberAnimation { target: sunWatermark; property: "opacity";  from: 0;   to: 0.5;  duration: 700; easing.type: Easing.OutCubic }
        NumberAnimation { target: sunWatermark; property: "scale";    from: 0.9; to: 1.0;  duration: 700; easing.type: Easing.OutCubic }
        NumberAnimation { target: sunWatermark; property: "rotation"; from: 0;   to: 25;   duration: 700; easing.type: Easing.OutCubic }
    }

    // ── Waiting animation: slow breathing while images load ───────────────────
    // Inhale 1.8 s → hold 0.4 s → exhale 2.2 s → rest 0.3 s  (≈ 4.7 s cycle)
    // No "from:" values — Qt reads the current property value so the first
    // cycle starts smoothly from wherever the splash left off (no flicker).
    // InOutSine gives a perfectly smooth sine-wave curve with no visible edges.
    SequentialAnimation {
        id: kioskHeartbeat
        loops: Animation.Infinite
        ParallelAnimation {
            NumberAnimation { target: splashLogo; property: "scale";   to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
            NumberAnimation { target: splashLogo; property: "opacity"; to: 1.0;  duration: 1800; easing.type: Easing.InOutSine }
        }
        PauseAnimation { duration: 400 }
        ParallelAnimation {
            NumberAnimation { target: splashLogo; property: "scale";   to: 1.0;  duration: 2200; easing.type: Easing.InOutSine }
            NumberAnimation { target: splashLogo; property: "opacity"; to: 0.5;  duration: 2200; easing.type: Easing.InOutSine }
        }
        PauseAnimation { duration: 300 }
    }

    // ── Kiosk launch: zoom logo out, then hand off to slideshow ───────────────
    SequentialAnimation {
        id: kioskLaunchAnim
        ParallelAnimation {
            NumberAnimation { target: splashLogo; property: "scale";   to: 4.5; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: splashLogo; property: "opacity"; to: 0;   duration: 400; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: root.startShow() }
    }

    // ── Launch transition overlay (background only) ────────────────────────
    Rectangle {
        id: launchOverlay
        anchors.fill: parent
        z: 200
        visible: false
        opacity: 0

        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgDeep }
            GradientStop { position: 1.0; color: Theme.bgGradEnd }
        }

        // Hide the cursor as soon as the overlay appears (start of launch animation)
        MouseArea { anchors.fill: parent; cursorShape: Qt.BlankCursor; hoverEnabled: true }
    }

    // Logo is a sibling of the overlay (z: 201) so it is never affected
    // by the overlay's opacity — it stays at full opacity throughout
    Image {
        id: launchLogo
        source: "../img/logo.svg"
        fillMode: Image.PreserveAspectFit
        width: 420; height: 126
        sourceSize.width: 1000; sourceSize.height: 300
        smooth: true; mipmap: true
        z: 201
        visible: false
    }

    SequentialAnimation {
        id: launchAnim

        // Snap logo to header position, make overlay ready
        ScriptAction {
            script: {
                var pos = headerLogo.mapToItem(root, 0, 0)
                launchLogo.x = pos.x
                launchLogo.y = pos.y
                launchLogo.scale = 1.0
                launchLogo.opacity = 1.0
                launchOverlay.opacity = 0
                launchOverlay.visible = true
                launchLogo.visible = true
                scrollTranslate.y = 0   // ensure clean start
                logoTranslate.y = 0
            }
        }

        // Fade overlay in while drifting settings content downward (logo counter-animated)
        ParallelAnimation {
            NumberAnimation {
                target: launchOverlay; property: "opacity"
                from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: scrollTranslate; property: "y"
                from: 0; to: 40; duration: 250; easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: logoTranslate; property: "y"
                from: 0; to: -40; duration: 250; easing.type: Easing.InQuad
            }
        }

        // Logo drifts to vertical centre of screen
        NumberAnimation {
            target: launchLogo; property: "y"
            to: root.height / 2 - launchLogo.height / 2
            duration: 450; easing.type: Easing.InOutCubic
        }

        PauseAnimation { duration: 400 }

        // Logo zooms toward the spectator and fades out
        ParallelAnimation {
            NumberAnimation {
                target: launchLogo; property: "scale"
                to: 4.5; duration: 300; easing.type: Easing.InQuart
            }
            NumberAnimation {
                target: launchLogo; property: "opacity"
                to: 0; duration: 300; easing.type: Easing.InQuart
            }
        }

        // Hand off to slideshow — hide overlay and reset translates so
        // the page is clean when the user returns via Esc
        ScriptAction {
            script: {
                launchOverlay.visible = false
                launchLogo.visible = false
                scrollTranslate.y = 0
                logoTranslate.y = 0
                sunWatermark.opacity = 0
                sunWatermark.scale = 0.9
                sunWatermark.rotation = 0
                root.startShow()
            }
        }
    }

}
