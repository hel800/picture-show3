// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

BasePopup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay.width - 32, 680)
    height: 640
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Capture the language and UI scale at app start so we can show restart
    // notices when the user changes them during this session.
    // Plain assignments (not bindings) so they stay fixed at the startup values.
    property string _startupLang: ""
    property int    _startupUiScale: 100
    Component.onCompleted: {
        _startupLang    = controller.language
        _startupUiScale = controller.uiScale
    }

    property int  _section: 0       // 0 Show · 1 Controls · 2 HUD · 3 Remote · 4 Misc
    property int  _focusedOption: 0 // index of focused option within current section
    property bool _doneFocused: false // Done button has keyboard focus

    // Options per section: Show=[duration,imageScale] Controls=[mouseNav] HUD=[size,style] Remote=[enable,port] Misc=[uiScale,language,updateCheck]
    readonly property var _optionCounts: [2, 1, 2, 2, 3]

    // Returns false for options that are currently inactive and should be skipped
    function _optionEnabled(section, option) {
        if (section === 3 && option === 1 && !controller.remoteEnabled) return false
        return true
    }

    // Always return focus to keyHandler for navigation.
    // Port editing is entered explicitly with Enter (see keyHandler below).
    function _updateOptionFocus() {
        keyHandler.forceActiveFocus()
        Qt.callLater(root._ensureFocusedVisible)
    }

    // Scroll the active tab's ScrollView so the focused option is fully visible.
    function _ensureFocusedVisible() {
        var flick = null
        var item  = null
        if (root._section === 0) {
            flick = genScroll.contentItem
            var g = [gen0Item, gen1Item]
            item = g[root._focusedOption]
        } else if (root._section === 1) {
            flick = ctrlScroll.contentItem
            item  = ctrl0Item
        } else if (root._section === 2) {
            flick = hudScroll.contentItem
            var h = [hud0Item, hud1Item]
            item = h[root._focusedOption]
        } else if (root._section === 3) {
            flick = remScroll.contentItem
            var r = [rem0Item, rem1Item]
            item = r[root._focusedOption]
        } else if (root._section === 4) {
            flick = miscScroll.contentItem
            var m = [misc0Item, misc1Item]
            item = m[root._focusedOption]
        }
        if (!flick || !item) return
        // item.mapToItem(flick, 0, 0).y gives visual y inside the Flickable;
        // adding contentY converts it back to content-space y.
        var top    = item.mapToItem(flick, 0, 0).y + flick.contentY
        var bottom = top + item.height
        if (top < flick.contentY)
            flick.contentY = Math.max(0, top)
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, bottom - flick.height)
    }

    // Returns true only when the given option is keyboard-highlighted.
    // False whenever the Done button has focus, so option highlights clear.
    function _isOptionFocused(section, option) {
        return !root._doneFocused && root._section === section && root._focusedOption === option
    }

    // If the focused option becomes disabled (e.g. remote turned off while Port was focused),
    // fall back to the first option.
    Connections {
        target: controller
        function onRemoteEnabledChanged() {
            if (!controller.remoteEnabled && root._section === 3 && root._focusedOption === 1)
                root._focusedOption = 0
            root._updateOptionFocus()
        }
    }

    onAboutToShow: { var w = parent ? parent.Window.window : null; if (w) w.advancedOpen = true }
    onAboutToHide: { var w = parent ? parent.Window.window : null; if (w) w.advancedOpen = false }
    onOpened: {
        root._doneFocused = false
        keyHandler.forceActiveFocus()
    }

    background: Rectangle {
        radius: 20
        color: Theme.bgCard
        border.color: Theme.surface
        border.width: 1
        transform: Translate { y: root._slideOffset }
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.5) }

    contentItem: ColumnLayout {
        spacing: 0
        transform: Translate { y: root._slideOffset }

        // ── Keyboard handler (zero-size, focus capture) ───────────────────────
        Item {
            id: keyHandler
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            focus: true

            Keys.onPressed: function(event) {
                var count = root._optionCounts[root._section]

                // ── Done button is keyboard-focused ───────────────────────────
                if (root._doneFocused) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
                        event.key === Qt.Key_Escape) {
                        root.close()
                    } else if (event.key === Qt.Key_Up) {
                        root._doneFocused = false
                        var last = count - 1
                        while (last >= 0 && !root._optionEnabled(root._section, last)) last--
                        if (last >= 0) root._focusedOption = last
                        root._updateOptionFocus()
                    } else if (event.key === Qt.Key_Tab) {
                        root._doneFocused = false
                        root._section = (root._section + 1) % 5
                        root._focusedOption = 0
                        root._updateOptionFocus()
                    } else if (event.key === Qt.Key_Backtab) {
                        root._doneFocused = false
                        root._section = (root._section + 4) % 5
                        root._focusedOption = 0
                        root._updateOptionFocus()
                    }
                    // Down / Left / Right on Done: no-op
                    event.accepted = true
                    return
                }

                // ── Normal option navigation ───────────────────────────────────
                if (event.key === Qt.Key_Tab) {
                    root._section = (root._section + 1) % 5
                    root._focusedOption = 0
                    root._updateOptionFocus()
                    event.accepted = true

                } else if (event.key === Qt.Key_Backtab) {
                    root._section = (root._section + 4) % 5
                    root._focusedOption = 0
                    root._updateOptionFocus()
                    event.accepted = true

                } else if (event.key === Qt.Key_Up) {
                    var prev = root._focusedOption - 1
                    while (prev >= 0 && !root._optionEnabled(root._section, prev)) prev--
                    if (prev >= 0) root._focusedOption = prev
                    root._updateOptionFocus()
                    event.accepted = true

                } else if (event.key === Qt.Key_Down) {
                    var next = root._focusedOption + 1
                    while (next < count && !root._optionEnabled(root._section, next)) next++
                    if (next < count) {
                        root._focusedOption = next
                    } else {
                        root._doneFocused = true   // wrap to Done button
                    }
                    root._updateOptionFocus()
                    event.accepted = true

                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    var d = (event.key === Qt.Key_Right) ? 1 : -1

                    if (root._isOptionFocused(0, 0)) {
                        controller.setTransitionDuration(
                            Math.max(100, Math.min(3000, controller.transitionDuration + d * 100)))

                    } else if (root._isOptionFocused(0, 1)) {
                        controller.setImageFill(d > 0)

                    } else if (root._isOptionFocused(4, 0)) {
                        controller.setUiScale(
                            Math.max(75, Math.min(300, controller.uiScale + d * 25)))

                    } else if (root._isOptionFocused(4, 1)) {
                        var langs = controller.availableLanguages
                        var idx = 0
                        for (var i = 0; i < langs.length; i++)
                            if (langs[i].code === controller.language) { idx = i; break }
                        controller.setLanguage(langs[(idx + d + langs.length) % langs.length].code)

                    } else if (root._isOptionFocused(4, 2)) {
                        controller.setUpdateCheckEnabled(d > 0)

                    } else if (root._isOptionFocused(2, 0)) {
                        controller.setHudSize(
                            Math.max(50, Math.min(200, controller.hudSize + d * 10)))

                    } else if (root._isOptionFocused(2, 1)) {
                        var hudStyles = ["fundamental", "floating"]
                        var hsi = hudStyles.indexOf(controller.hudStyle)
                        controller.setHudStyle(hudStyles[(hsi + d + hudStyles.length) % hudStyles.length])

                    } else if (root._isOptionFocused(1, 0)) {
                        controller.setMouseNavEnabled(d > 0)

                    } else if (root._isOptionFocused(3, 0)) {
                        controller.setRemoteEnabled(d > 0)
                    }
                    event.accepted = true

                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) &&
                           root._section === 3 && root._focusedOption === 1 &&
                           controller.remoteEnabled) {
                    // Enter on the Port option → enter edit mode
                    portField.forceActiveFocus()
                    portField.selectAll()
                    event.accepted = true
                }
            }
        }

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 20

            Text {
                text: qsTr("ADVANCED SETTINGS")
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 1.4
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 28; height: 28; radius: 8
                color: closeHover.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.textMuted; font.pixelSize: 12 }
                MouseArea {
                    id: closeHover
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // ── Section tabs (segmented control) ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            height: 36; radius: 10; color: Theme.surface

            Row {
                anchors { fill: parent; margins: 3 }
                spacing: 3

                Repeater {
                    model: [qsTr("Show"), qsTr("Controls"), qsTr("HUD"), qsTr("Remote"), qsTr("Misc")]
                    delegate: Rectangle {
                        height: parent.height
                        width: Math.floor((parent.width - 12) / 5)
                        radius: 8
                        color: root._section === index ? Theme.bgCard
                               : (tabHover.containsMouse ? Theme.surfaceHover : "transparent")
                        border.color: root._section === index ? Theme.accent : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: tabLabel; anchors.centerIn: parent; text: modelData
                            font.pixelSize: 12
                            font.weight: root._section === index ? Font.Medium : Font.Normal
                            color: root._section === index ? Theme.accentLight : Theme.textMuted
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: tabHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root._section = index; root._focusedOption = 0; keyHandler.forceActiveFocus() }
                        }
                    }
                }
            }
        }

        // ── Keyboard hints row ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 26
            spacing: 4

            Item { Layout.fillWidth: true }
            KeyHint { label: "Tab"; Layout.alignment: Qt.AlignVCenter }
            Text { text: qsTr("sections"); color: Theme.textDisabled; font.pixelSize: 10; leftPadding: 2 }
            Item { width: 10 }
            KeyHint { label: "↑"; Layout.alignment: Qt.AlignVCenter }
            KeyHint { label: "↓"; Layout.alignment: Qt.AlignVCenter }
            Text { text: qsTr("option"); color: Theme.textDisabled; font.pixelSize: 10; leftPadding: 2 }
            Item { width: 10 }
            KeyHint { label: "←"; Layout.alignment: Qt.AlignVCenter }
            KeyHint { label: "→"; Layout.alignment: Qt.AlignVCenter }
            Text { text: qsTr("change"); color: Theme.textDisabled; font.pixelSize: 10; leftPadding: 2 }
            Item { Layout.fillWidth: true }
        }

        // ── Section content ────────────────────────────────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root._section

            // ── Show ──────────────────────────────────────────────────────────
            Item {
                ScrollView {
                    id: genScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: genScroll.availableWidth
                    spacing: 0

                    // Option 0: Transition Duration ──────────────────────────
                    Item {
                        id: gen0Item
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        implicitHeight: gen0Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(0, 0)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: gen0Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(0, 0)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("TRANSITION")
                                    color: root._isOptionFocused(0, 0)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 10
                                Text { text: qsTr("Duration"); color: Theme.textPrimary; font.pixelSize: 14 }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (durationSlider.value / 1000).toFixed(1) + " s"
                                    color: Theme.accentLight; font.pixelSize: 13; font.weight: Font.Medium
                                }
                            }
                            Slider {
                                id: durationSlider
                                Layout.fillWidth: true; Layout.bottomMargin: 6
                                from: 100; to: 3000; stepSize: 100
                                value: controller.transitionDuration
                                onMoved: controller.setTransitionDuration(value)
                                background: Rectangle {
                                    x: durationSlider.leftPadding
                                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                                    width: durationSlider.availableWidth; height: 4; radius: 2
                                    color: Theme.surface
                                    Rectangle { width: durationSlider.visualPosition * parent.width; height: parent.height; color: Theme.accent; radius: 2 }
                                }
                                handle: Rectangle {
                                    x: durationSlider.leftPadding + durationSlider.visualPosition * (durationSlider.availableWidth - width)
                                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                                    width: 22; height: 22; radius: 11
                                    color: Theme.accentLight; border.color: Theme.accent; border.width: 2
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "0.1 s"; color: Theme.textDisabled; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Text { text: "3.0 s"; color: Theme.textDisabled; font.pixelSize: 11 }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                    // Option 1: Image scale ───────────────────────────────────
                    Item {
                        id: gen1Item
                        Layout.fillWidth: true
                        implicitHeight: gen1Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(0, 1)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: gen1Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(0, 1)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("IMAGE SCALE")
                                    color: root._isOptionFocused(0, 1)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 4; spacing: 12
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Image scale"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("How images are scaled to fit the window"); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { label: qsTr("Fit"),  icon: "../img/icon_scale_fit.svg",  fill: false },
                                            { label: qsTr("Fill"), icon: "../img/icon_scale_fill.svg", fill: true  }
                                        ]
                                        delegate: Rectangle {
                                            width: 66; height: 50; radius: 12
                                            color: controller.imageFill === modelData.fill
                                                   ? Theme.accentDeep
                                                   : (scaleArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                                            border.color: controller.imageFill === modelData.fill ? Theme.accent : "transparent"
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 3
                                                ThemedIcon {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    source: modelData.icon
                                                    size: 20
                                                    iconColor: controller.imageFill === modelData.fill
                                                               ? Theme.accentLight : Theme.textMuted
                                                    Behavior on iconColor { ColorAnimation { duration: 150 } }
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.label; font.pixelSize: 11
                                                    color: controller.imageFill === modelData.fill
                                                           ? Theme.textPrimary : Theme.textMuted
                                                }
                                            }
                                            MouseArea {
                                                id: scaleArea; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: controller.setImageFill(modelData.fill)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
                } // ScrollView
            }

            // ── Controls ──────────────────────────────────────────────────────
            Item {
                ScrollView {
                    id: ctrlScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: ctrlScroll.availableWidth
                    spacing: 0

                    // Option 0: Mouse navigation ──────────────────────────────
                    Item {
                        id: ctrl0Item
                        Layout.fillWidth: true
                        implicitHeight: ctrl0Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(1, 0)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: ctrl0Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(1, 0)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("MOUSE")
                                    color: root._isOptionFocused(1, 0)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 4
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Mouse button navigation"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("Left click → next  ·  Right click → previous"); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Switch {
                                    id: mouseNavSwitch
                                    checked: controller.mouseNavEnabled
                                    onToggled: controller.setMouseNavEnabled(checked)
                                    indicator: Rectangle {
                                        implicitWidth: 44; implicitHeight: 24; radius: 12
                                        color: mouseNavSwitch.checked ? Theme.accent : Theme.surface
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Rectangle {
                                            x: mouseNavSwitch.checked ? parent.width - width - 3 : 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 18; height: 18; radius: 9
                                            color: mouseNavSwitch.checked ? "white" : Theme.textMuted
                                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                } // ScrollView
            }

            // ── HUD ───────────────────────────────────────────────────────────
            Item {
                ScrollView {
                    id: hudScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: hudScroll.availableWidth
                    spacing: 0

                    // Option 0: HUD Size ──────────────────────────────────────
                    Item {
                        id: hud0Item
                        Layout.fillWidth: true
                        implicitHeight: hud0Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(2, 0)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: hud0Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(2, 0)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("HUD")
                                    color: root._isOptionFocused(2, 0)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 10
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Size"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("Applied on top of the global UI scale"); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: hudSizeSlider.value + " %"
                                    color: Theme.accentLight; font.pixelSize: 13; font.weight: Font.Medium
                                }
                            }
                            Slider {
                                id: hudSizeSlider
                                Layout.fillWidth: true; Layout.bottomMargin: 6
                                from: 50; to: 200; stepSize: 10
                                value: controller.hudSize
                                onMoved: controller.setHudSize(value)
                                background: Rectangle {
                                    x: hudSizeSlider.leftPadding
                                    y: hudSizeSlider.topPadding + hudSizeSlider.availableHeight / 2 - height / 2
                                    width: hudSizeSlider.availableWidth; height: 4; radius: 2
                                    color: Theme.surface
                                    Rectangle { width: hudSizeSlider.visualPosition * parent.width; height: parent.height; color: Theme.accent; radius: 2 }
                                }
                                handle: Rectangle {
                                    x: hudSizeSlider.leftPadding + hudSizeSlider.visualPosition * (hudSizeSlider.availableWidth - width)
                                    y: hudSizeSlider.topPadding + hudSizeSlider.availableHeight / 2 - height / 2
                                    width: 22; height: 22; radius: 11
                                    color: Theme.accentLight; border.color: Theme.accent; border.width: 2
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "50 %"; color: Theme.textDisabled; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Text { text: "200 %"; color: Theme.textDisabled; font.pixelSize: 11 }
                            }
                        }
                    }

                    // Option 1: HUD Style ─────────────────────────────────────
                    Item {
                        id: hud1Item
                        Layout.fillWidth: true
                        implicitHeight: hud1Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(2, 1)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: hud1Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(2, 1)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("HUD STYLE")
                                    color: root._isOptionFocused(2, 1)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 4; spacing: 12
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("HUD style"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("Bar: slim and unobtrusive. Floating: larger, more prominent."); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { label: qsTr("Bar"),         icon: "../img/icon_hud_fundamental.svg", style: "fundamental" },
                                            { label: qsTr("Floating"),    icon: "../img/icon_hud_floating.svg",    style: "floating"     }
                                        ]
                                        delegate: Rectangle {
                                            width: 76; height: 50; radius: 12
                                            color: controller.hudStyle === modelData.style
                                                   ? Theme.accentDeep
                                                   : (hudStyleArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                                            border.color: controller.hudStyle === modelData.style ? Theme.accent : "transparent"
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 3
                                                ThemedIcon {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    source: modelData.icon
                                                    size: 20
                                                    iconColor: controller.hudStyle === modelData.style
                                                               ? Theme.accentLight : Theme.textMuted
                                                    Behavior on iconColor { ColorAnimation { duration: 150 } }
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.label; font.pixelSize: 11
                                                    color: controller.hudStyle === modelData.style
                                                           ? Theme.textPrimary : Theme.textMuted
                                                }
                                            }
                                            MouseArea {
                                                id: hudStyleArea; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: controller.setHudStyle(modelData.style)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                } // ScrollView
            }

            // ── Remote ────────────────────────────────────────────────────────
            Item {
                ScrollView {
                    id: remScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: remScroll.availableWidth
                    spacing: 0

                    // Option 0: Enable ────────────────────────────────────────
                    Item {
                        id: rem0Item
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        implicitHeight: rem0Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(3, 0)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: rem0Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(3, 0)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("SMARTPHONE REMOTE")
                                    color: root._isOptionFocused(3, 0)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: qsTr("Enable remote control"); color: Theme.textPrimary; font.pixelSize: 14 }
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
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                    // Option 1: Port ──────────────────────────────────────────
                    Item {
                        id: rem1Item
                        Layout.fillWidth: true
                        implicitHeight: rem1Inner.implicitHeight + 24
                        opacity: controller.remoteEnabled ? 1.0 : 0.35
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(3, 1)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: rem1Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(3, 1)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("PORT")
                                    color: root._isOptionFocused(3, 1)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: qsTr("Port"); color: Theme.textPrimary; font.pixelSize: 14 }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 90; height: 32; radius: 8; color: Theme.surface
                                    border.color: portField.activeFocus ? Theme.accent : Theme.borderMuted
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 100 } }
                                    TextInput {
                                        id: portField
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: controller.remotePort.toString()
                                        color: Theme.textPrimary; font.pixelSize: 13
                                        enabled: controller.remoteEnabled
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1024; top: 65535 }
                                        // Save whenever focus leaves the field
                                        onActiveFocusChanged: {
                                            if (!activeFocus && acceptableInput)
                                                controller.setRemotePort(parseInt(text))
                                        }
                                        // Navigation keys exit edit mode.
                                        // Qt.callLater defers the focus handback until after
                                        // the full event-delivery stack unwinds, which is the
                                        // only reliable way to prevent the TextInput's own
                                        // internal handling from re-claiming focus.
                                        // Navigation state is updated here too so the action
                                        // takes effect even though the key was consumed.
                                        Keys.onPressed: function(event) {
                                            var count = root._optionCounts[root._section]
                                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
                                                event.key === Qt.Key_Escape) {
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)

                                            } else if (event.key === Qt.Key_Tab) {
                                                root._section = (root._section + 1) % 5
                                                root._focusedOption = 0
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)

                                            } else if (event.key === Qt.Key_Backtab) {
                                                root._section = (root._section + 4) % 5
                                                root._focusedOption = 0
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)

                                            } else if (event.key === Qt.Key_Up) {
                                                var prev = root._focusedOption - 1
                                                while (prev >= 0 && !root._optionEnabled(root._section, prev)) prev--
                                                if (prev >= 0) root._focusedOption = prev
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)

                                            } else if (event.key === Qt.Key_Down) {
                                                var next = root._focusedOption + 1
                                                while (next < count && !root._optionEnabled(root._section, next)) next++
                                                if (next < count) root._focusedOption = next
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                } // ScrollView
            }

            // ── Misc ──────────────────────────────────────────────────────────
            Item {
                ScrollView {
                    id: miscScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: miscScroll.availableWidth
                    spacing: 0

                    // Option 0: UI Scale ──────────────────────────────────────
                    Item {
                        id: misc0Item
                        Layout.fillWidth: true
                        implicitHeight: misc0Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(4, 0)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: misc0Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 10; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(4, 0)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("UI SCALE")
                                    color: root._isOptionFocused(4, 0)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 10
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Global UI scale factor"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("Scales all menus, dialogs, and controls"); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: uiScaleSlider.value + " %"
                                    color: Theme.accentLight; font.pixelSize: 13; font.weight: Font.Medium
                                }
                            }
                            Slider {
                                id: uiScaleSlider
                                Layout.fillWidth: true; Layout.bottomMargin: 6
                                from: 75; to: 300; stepSize: 25
                                value: controller.uiScale
                                onMoved: controller.setUiScale(value)
                                background: Rectangle {
                                    x: uiScaleSlider.leftPadding
                                    y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                    width: uiScaleSlider.availableWidth; height: 4; radius: 2
                                    color: Theme.surface
                                    Rectangle { width: uiScaleSlider.visualPosition * parent.width; height: parent.height; color: Theme.accent; radius: 2 }
                                }
                                handle: Rectangle {
                                    x: uiScaleSlider.leftPadding + uiScaleSlider.visualPosition * (uiScaleSlider.availableWidth - width)
                                    y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                    width: 22; height: 22; radius: 11
                                    color: Theme.accentLight; border.color: Theme.accent; border.width: 2
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 4
                                Text { text: "75 %"; color: Theme.textDisabled; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Text { text: "300 %"; color: Theme.textDisabled; font.pixelSize: 11 }
                            }
                            Text {
                                visible: controller.uiScale !== root._startupUiScale
                                text: qsTr("⚠  Restart the app to apply the scale change.")
                                color: Theme.statusWarn; font.pixelSize: 11
                                wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.bottomMargin: 4
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                    // Option 1: Language ──────────────────────────────────────
                    Item {
                        id: misc1Item
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        implicitHeight: misc1Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(4, 1)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: misc1Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(4, 1)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("LANGUAGE")
                                    color: root._isOptionFocused(4, 1)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true; Layout.bottomMargin: 8; spacing: 8
                                Repeater {
                                    model: controller.availableLanguages
                                    delegate: Rectangle {
                                        height: 32; width: langLabel.implicitWidth + 24; radius: 10
                                        color: controller.language === modelData.code
                                               ? Theme.accentDeep
                                               : (langArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                                        border.color: controller.language === modelData.code ? Theme.accent : "transparent"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            id: langLabel; anchors.centerIn: parent
                                            text: modelData.code === "auto" ? qsTr("Auto") : modelData.name
                                            font.pixelSize: 12
                                            color: controller.language === modelData.code ? Theme.textPrimary : Theme.textMuted
                                        }
                                        MouseArea {
                                            id: langArea; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: controller.setLanguage(modelData.code)
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: controller.language !== root._startupLang
                                text: qsTr("⚠  Restart the app to apply the language change.")
                                color: Theme.statusWarn; font.pixelSize: 11
                                wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                    // Option 2: Update check ──────────────────────────────────
                    Item {
                        id: misc2Item
                        Layout.fillWidth: true
                        implicitHeight: misc2Inner.implicitHeight + 24
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: root._isOptionFocused(4, 2)
                                   ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        ColumnLayout {
                            id: misc2Inner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 12; spacing: 8
                                Rectangle {
                                    width: 3; height: 11; radius: 1.5
                                    color: root._isOptionFocused(4, 2)
                                           ? Theme.accent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: qsTr("UPDATES")
                                    color: root._isOptionFocused(4, 2)
                                           ? Theme.accentLight : Theme.textMuted
                                    font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.bottomMargin: 4
                                Column {
                                    spacing: 2
                                    Text { text: qsTr("Check for updates on startup"); color: Theme.textPrimary; font.pixelSize: 14 }
                                    Text { text: qsTr("Checks GitHub Releases for a newer version"); color: Theme.textMuted; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                Switch {
                                    id: updateCheckSwitch
                                    checked: controller.updateCheckEnabled
                                    onToggled: controller.setUpdateCheckEnabled(checked)
                                    indicator: Rectangle {
                                        implicitWidth: 44; implicitHeight: 24; radius: 12
                                        color: updateCheckSwitch.checked ? Theme.accent : Theme.surface
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Rectangle {
                                            x: updateCheckSwitch.checked ? parent.width - width - 3 : 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 18; height: 18; radius: 9
                                            color: updateCheckSwitch.checked ? "white" : Theme.textMuted
                                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                } // ScrollView
            }
        }

        // ── Done button ───────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.surface; Layout.topMargin: 16; Layout.bottomMargin: 16 }

        Rectangle {
            Layout.fillWidth: true; height: 44; radius: 10
            color: root._doneFocused ? Theme.accentDeep
                   : (doneArea.containsMouse ? Theme.surfaceHover : Theme.surface)
            border.color: root._doneFocused ? Theme.accent : "transparent"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent; text: qsTr("Done")
                color: root._doneFocused ? Theme.accentLight : Theme.textPrimary
                font.pixelSize: 14; font.weight: Font.Medium
            }
            MouseArea {
                id: doneArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.close()
            }
        }
    }

    // Pad the content
    leftPadding: 28; rightPadding: 28; topPadding: 24; bottomPadding: 24
}
