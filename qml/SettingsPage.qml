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
import QtQuick.Dialogs
import "."

Item {
    id: root
    focus: true

    // ── Inline reusable components ───────────────────────────────────────────
    component KeyHint: Rectangle {
        property string label: ""
        width: 20; height: 20; radius: 5
        color: Theme.surface
        border.color: Theme.textSubtle
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: Theme.textSecondary
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }
    property bool   hasStarted    : false
    property string _folderAtStart: ""

    // Reset to "Start" when the user picks a different folder after a show
    Connections {
        target: controller
        function onSettingsChanged() {
            if (root.hasStarted && controller.folder !== root._folderAtStart)
                root.hasStarted = false
        }
    }

    signal startShow()

    function launchShow() {
        if (controller.imageCount === 0) return
        launchAnim.restart()
    }

    Keys.onPressed: function(event) {
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
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Exit Application"
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "Do you want to exit the application?"
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
                            text: "No"
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
                            text: "Yes"
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
        title: "Select image folder"
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

    // ── Scroll area ────────────────────────────────────────────────────────────
    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: mainCol
            width: Math.min(root.width - 32, 680)
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
                Layout.preferredWidth: 500
                Layout.preferredHeight: 150
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                smooth: true
                mipmap: true
                opacity: 0
            }

            Item { Layout.preferredHeight: 32 }

            // ── Settings card ─────────────────────────────────────────────────
            Rectangle {
                id: card
                Layout.fillWidth: true
                radius: 20
                color: Theme.bgCard
                border.color: Theme.surface
                border.width: 1
                implicitHeight: cardCol.implicitHeight + 56

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: 28
                    }
                    spacing: 24

                    // ── Folder picker ─────────────────────────────────────────
                    Text {
                        text: "IMAGE FOLDER"
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
                                onEditingFinished: controller.loadFolder(text)

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
                                    text: "Type a path or click Browse…"
                                    color: Theme.surfaceHover
                                    font.pixelSize: 13
                                    visible: parent.text.length === 0
                                }
                            }
                        }

                        // Browse button
                        Rectangle {
                            width: 110; height: 44
                            radius: 10
                            color: browseArea.containsMouse ? Theme.surfaceHover : Theme.surface
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Browse..."
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
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "🕐"
                                    font.pixelSize: 18
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
                            implicitHeight: recentCol.implicitHeight + 32
                            focus: true

                            Keys.onPressed: function(event) {
                                var count = controller.folderHistory.length
                                switch (event.key) {
                                case Qt.Key_Up:
                                    if (recentPopup.selectedIndex > 0) recentPopup.selectedIndex--
                                    event.accepted = true
                                    break
                                case Qt.Key_Down:
                                    if (recentPopup.selectedIndex < count - 1) recentPopup.selectedIndex++
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
                                id: recentCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                spacing: 6

                                Text {
                                    text: "Recent Folders"
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.letterSpacing: 1.4
                                    leftPadding: 4
                                    bottomPadding: 4
                                }

                                Repeater {
                                    model: controller.folderHistory

                                    delegate: Rectangle {
                                        width: recentCol.width
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

                                // Divider + clear
                                Rectangle { width: recentCol.width; height: 1; color: Theme.surface }

                                Rectangle {
                                    width: recentCol.width
                                    height: 36
                                    radius: 10
                                    color: clearArea.containsMouse ? Theme.surface : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Clear history"
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

                    Text {
                        visible: controller.folder.length > 0
                        text: controller.imageCount > 0
                              ? "✓  " + controller.imageCount + " images found"
                              : "⚠  No supported images found in this folder"
                        color: controller.imageCount > 0 ? Theme.statusOk : Theme.statusWarn
                        font.pixelSize: 12
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
                                  ? (root.hasStarted ? "▶  Resume Picture Show" : "▶  Start Picture Show")
                                  : "Select a folder to continue"
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
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "TRANSITION"
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
                                { id: "fade",      label: "Fade",       icon: "✦" },
                                { id: "slide",     label: "Slide",      icon: "→" },
                                { id: "zoom",      label: "Zoom",       icon: "⊕" },
                                { id: "fadeblack", label: "Fade/Black", icon: "◑" }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 58
                                radius: 12
                                color: controller.transitionStyle === modelData.id
                                       ? Theme.accentDeep : Theme.surface
                                border.color: controller.transitionStyle === modelData.id
                                              ? Theme.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon; font.pixelSize: 20
                                        color: Theme.textPrimary
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label; font.pixelSize: 11
                                        color: controller.transitionStyle === modelData.id
                                               ? Theme.textPrimary : Theme.textMuted
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controller.setTransitionStyle(modelData.id)
                                }
                            }
                        }
                    }

                    // ── Divider ───────────────────────────────────────────────
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface }

                    // ── Sort order ────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "SORT ORDER"
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
                                { id: "name",   label: "By Name", icon: "🔤" },
                                { id: "date",   label: "By Date", icon: "📅" },
                                { id: "random", label: "Random",  icon: "🔀" }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 58
                                radius: 12
                                color: controller.sortOrder === modelData.id
                                       ? Theme.accentDeep : Theme.surface
                                border.color: controller.sortOrder === modelData.id
                                              ? Theme.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon; font.pixelSize: 20
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label; font.pixelSize: 11
                                        color: controller.sortOrder === modelData.id
                                               ? Theme.textPrimary : Theme.textMuted
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controller.setSortOrder(modelData.id)
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
                                    Text { text: "Loop"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { text: "Repeat after last photo"; color: Theme.textMuted; font.pixelSize: 11 }
                                }

                                Item { Layout.fillWidth: true }

                                KeyHint { label: "L" }

                                // Custom toggle switch
                                Rectangle {
                                    width: 44; height: 24; radius: 12
                                    color: controller.loop ? Theme.accent : Theme.textDisabled
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Rectangle {
                                        width: 18; height: 18; radius: 9
                                        color: "white"
                                        x: controller.loop ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
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
                                    Text { text: "Autoplay"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { text: "Advance automatically"; color: Theme.textMuted; font.pixelSize: 11 }
                                }

                                Item { Layout.fillWidth: true }

                                KeyHint { label: "A" }

                                Rectangle {
                                    width: 44; height: 24; radius: 12
                                    color: controller.autoplay ? Theme.accent : Theme.textDisabled
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Rectangle {
                                        width: 18; height: 18; radius: 9
                                        color: "white"
                                        x: controller.autoplay ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
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
                            Text { text: "Interval"; color: Theme.textSecondary; font.pixelSize: 13 }
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

                        Text { text: "📱"; font.pixelSize: 26 }

                        Column {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Smartphone Remote"; color: Theme.textPrimary; font.pixelSize: 13; font.weight: Font.Medium }
                            Text {
                                text: "Open " + remoteServer.url + " on your phone during the show"
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

                    // ── Advanced settings link ────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 32; radius: 8
                            width: advancedLabel.implicitWidth + 24
                            color: advancedArea.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: advancedLabel
                                anchors.centerIn: parent
                                text: "Advanced settings ›"
                                color: Theme.textMuted
                                font.pixelSize: 12
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

                    Item { Layout.preferredHeight: 4 }
                } // end cardCol
            } // end card

            AdvancedSettingsDialog { id: advancedDialog }

            // ── Keyboard hint ─────────────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 14
                text: "← →  Navigate    Space  Play/Pause    F  Fullscreen    Esc  Exit"
                color: Theme.textGhost
                font.pixelSize: 11
                font.letterSpacing: 0.3
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                text: "v" + appVersion
                color: Theme.textGhost
                font.pixelSize: 10
                font.letterSpacing: 0.3
            }

            Item { Layout.preferredHeight: 48 }
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
            x: parent.width / 2 - width / 2
            y: parent.height / 2 - height / 2
            smooth: true
            mipmap: true
            opacity: 0
            scale: 0.88
        }

        SequentialAnimation {
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

            // Swap: reveal header logo then instantly hide the overlay
            ScriptAction {
                script: {
                    headerLogo.opacity = 1
                    splashOverlay.visible = false
                }
            }
        }
    }
    // ── Launch transition overlay ──────────────────────────────────────────
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

        Image {
            id: launchLogo
            source: "../img/logo.svg"
            fillMode: Image.PreserveAspectFit
            width: 500; height: 150
            smooth: true; mipmap: true
        }
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
            }
        }

        // Fade overlay in to cover settings content
        NumberAnimation {
            target: launchOverlay; property: "opacity"
            from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad
        }

        // Logo drifts to vertical centre of screen
        NumberAnimation {
            target: launchLogo; property: "y"
            to: root.height / 2 - launchLogo.height / 2
            duration: 450; easing.type: Easing.InOutCubic
        }

        PauseAnimation { duration: 100 }

        // Logo zooms toward the spectator and fades out
        ParallelAnimation {
            NumberAnimation {
                target: launchLogo; property: "scale"
                to: 2.8; duration: 500; easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: launchLogo; property: "opacity"
                to: 0; duration: 500; easing.type: Easing.InCubic
            }
        }

        // Hand off to slideshow — hide overlay first so it's gone when we return
        ScriptAction {
            script: {
                launchOverlay.visible = false
                root.startShow()
            }
        }
    }

}
