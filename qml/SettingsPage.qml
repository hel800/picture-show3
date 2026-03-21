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
    property bool   hasStarted       : false
    property string _folderAtStart   : ""
    property string _sortAtStart     : ""
    property int    _minRatingAtStart: 0

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

    function launchShow() {
        if (controller.imageCount === 0) return
        if (root.hasStarted)
            root.startShow()   // resume: skip fancy transition, show fades in via SlideshowPage intro
        else
            launchAnim.restart()
    }

    function triggerSlideIn() {
        scrollTranslate.y = 20
        scrollSlideIn.start()
    }

    Keys.onPressed: function(event) {
        if (launchAnim.running || splashAnim.running) { event.accepted = true; return }
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
            quitDialog.open()
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (controller.imageCount > 0)
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
        case Qt.Key_Question:
            root.openHelp()
            break
        default:
            break
        }
        event.accepted = true
    }

    // ── Quit confirmation dialog ───────────────────────────────────────────────
    Popup {
        id: quitDialog
        anchors.centerIn: parent
        width: 340
        height: dialogContent.implicitHeight + 48
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose   // we handle Esc ourselves

        background: Rectangle {
            radius: 20
            color: Theme.bgCard
            border.color: Theme.surface
            border.width: 1
        }

        Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        onOpened: yesBtn.forceActiveFocus()
        onClosed: root.forceActiveFocus()

        // Inner Item is a proper Item so Keys can attach to it
        Item {
            id: dialogContent
            anchors.fill: parent
            focus: true
            implicitHeight: dialogCol.implicitHeight

            Keys.onPressed: function(event) {
                switch (event.key) {
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (noBtn.activeFocus) quitDialog.close()
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
                    if (yesBtn.activeFocus) noBtn.forceActiveFocus()
                    else yesBtn.forceActiveFocus()
                    break
                default:
                    break
                }
                event.accepted = true
            }

            ColumnLayout {
                id: dialogCol
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
                        id: noBtn
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

                    Rectangle {
                        id: yesBtn
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
                }
            }
        }
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
            Item { Layout.preferredHeight: 44 }

            Image {
                id: headerLogo
                source: "../img/logo.svg"
                fillMode: Image.PreserveAspectFit
                width: 500
                height: 150
                sourceSize.width: 1000
                sourceSize.height: 300
                Layout.preferredWidth: 500
                Layout.preferredHeight: 150
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                smooth: true
                mipmap: true
                opacity: 0
                transform: Translate { id: logoTranslate; y: 0 }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 32 }

            // ── Settings card ─────────────────────────────────────────────────
            Rectangle {
                id: card
                Layout.fillWidth: true
                radius: 20
                color: Theme.bgCard
                border.color: Theme.surface
                border.width: 1
                implicitHeight: cardCol.implicitHeight + 44

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: 28
                    }
                    spacing: 24

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
                            height: 44
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
                            width: 124; height: 44
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
                            width: 64; height: 44
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
                    Popup {
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
                        }

                        Overlay.modal: Rectangle {
                            color: Qt.rgba(0, 0, 0, 0.5)
                        }

                        contentItem: Item {
                            id: recentContentItem
                            implicitHeight: Math.min(recentOuterCol.implicitHeight + 32, root.height / 2)
                            focus: true

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
                                                width: recentListCol.width - 10
                                                height: 40
                                                radius: 10
                                                color: (recentPopup.selectedIndex === index)
                                                       ? Theme.accentDeep
                                                       : (recentItemArea.containsMouse ? Theme.surface : "transparent")
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                border.color: recentPopup.selectedIndex === index ? Theme.accent : "transparent"
                                                border.width: 1

                                                Text {
                                                    anchors { left: parent.left; right: parent.right
                                                              verticalCenter: parent.verticalCenter
                                                              leftMargin: 12; rightMargin: 12 }
                                                    text: modelData
                                                    color: recentPopup.selectedIndex === index ? Theme.textPrimary : Theme.textPrimary
                                                    font.pixelSize: 13
                                                    elide: Text.ElideLeft
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

                    Row {
                        visible: controller.folder.length > 0
                        spacing: 0
                        Text {
                            text: controller.imageCount > 0
                                  ? qsTr("✓  %1 images found").arg(controller.imageCount)
                                  : qsTr("⚠  No supported images found in this folder")
                            color: controller.imageCount > 0 ? Theme.statusOk : Theme.statusWarn
                            font.pixelSize: 12
                        }
                        Text {
                            visible: controller.imageCount < controller.totalImageCount
                            text: qsTr("  ·  filter active")
                            color: Theme.textMuted
                            font.pixelSize: 12
                        }
                    }

                    // ── Start button ──────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 54
                        radius: 14
                        color: controller.imageCount > 0
                               ? (startArea.pressed ? Theme.accentPress : Theme.accent)
                               : Theme.surface
                        Behavior on color { ColorAnimation { duration: 180 } }

                        Text {
                            anchors.centerIn: parent
                            text: controller.imageCount > 0
                                  ? (root.hasStarted ? qsTr("▶  Resume Picture Show") : qsTr("▶  Start Picture Show"))
                                  : qsTr("Select a folder to continue")
                            color: controller.imageCount > 0 ? "white" : Theme.textDisabled
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }

                        KeyHint {
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            label: "↵"
                            opacity: controller.imageCount > 0 ? 1 : 0
                        }

                        MouseArea {
                            id: startArea
                            anchors.fill: parent
                            enabled: controller.imageCount > 0
                            cursorShape: controller.imageCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
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
                                    height: 58
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
                                        height: 58
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
                                Layout.fillWidth: true; height: 58
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
                            height: 64
                            radius: 12
                            color: Theme.surface

                            RowLayout {
                                anchors { fill: parent; margins: 16 }

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
                            height: 64
                            radius: 12
                            color: Theme.surface

                            RowLayout {
                                anchors { fill: parent; margins: 16 }

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
                                text: (intervalSlider.value / 1000).toFixed(1) + " s"
                                color: Theme.accentLight; font.pixelSize: 13; font.weight: Font.Medium
                            }
                        }

                        Slider {
                            id: intervalSlider
                            Layout.fillWidth: true
                            from: 1000; to: 30000; stepSize: 500
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
                            width: 44; height: 44
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
                                KeyHint { anchors.verticalCenter: parent.verticalCenter; label: "?" }
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
                Layout.topMargin: 14
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("In show commands:")
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
                Layout.topMargin: 14
                text: "v" + appVersion
                color: Theme.surfaceHover
                font.pixelSize: 11
                font.letterSpacing: 0.3
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 48 }
        }
    }

    // ── Welcome splash overlay ──────────────────────────────────────────────
    Rectangle {
        id: splashOverlay
        anchors.fill: parent
        z: 100
        visible: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgDeep }
            GradientStop { position: 1.0; color: Theme.bgGradEnd }
        }

        Image {
            id: splashLogo
            source: "../img/logo.svg"
            fillMode: Image.PreserveAspectFit
            width: 500
            height: 150
            sourceSize.width: 1000
            sourceSize.height: 300
            x: parent.width / 2 - width / 2
            y: parent.height / 2 - height / 2
            smooth: true
            mipmap: true
            opacity: 0
            scale: 0.88
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

            // Logo drifts up to its header position (overlay stays opaque)
            NumberAnimation {
                target: splashLogo; property: "y"
                to: 44
                duration: 500; easing.type: Easing.InOutCubic
            }

            // Swap: reveal header logo then instantly hide the overlay,
            // then slide the content up from its offset position
            ScriptAction {
                script: {
                    headerLogo.opacity = 1
                    splashOverlay.visible = false
                    scrollSlideIn.start()
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
    }

    // Logo is a sibling of the overlay (z: 201) so it is never affected
    // by the overlay's opacity — it stays at full opacity throughout
    Image {
        id: launchLogo
        source: "../img/logo.svg"
        fillMode: Image.PreserveAspectFit
        width: 500; height: 150
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
