// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Popup {
    id: root
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay.width - 32, 680)
    height: 640
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale";   from: 0.92; to: 1; duration: 250; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale";   from: 1; to: 0.92; duration: 200; easing.type: Easing.InCubic }
        }
    }

    // Capture the language at app start so we can show the restart notice
    // when the user picks a different language during this session.
    // Plain assignment (not a binding) so it stays fixed at the startup value.
    property string _startupLang: ""
    Component.onCompleted: _startupLang = controller.language

    property int  _section: 0       // 0 General · 1 Controls · 2 HUD · 3 Remote
    property int  _focusedOption: 0 // index of focused option within current section
    property bool _doneFocused: false // Done button has keyboard focus

    // Options per section: General=[duration,language] Controls=[mouseNav] HUD=[size] Remote=[enable,port]
    readonly property var _optionCounts: [2, 1, 1, 2]

    // Returns false for options that are currently inactive and should be skipped
    function _optionEnabled(section, option) {
        if (section === 3 && option === 1 && !controller.remoteEnabled) return false
        return true
    }

    // Always return focus to keyHandler for navigation.
    // Port editing is entered explicitly with Enter (see keyHandler below).
    function _updateOptionFocus() {
        keyHandler.forceActiveFocus()
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

    onOpened: {
        var w = parent ? parent.Window.window : null
        if (w) w.advancedOpen = true
        root._doneFocused = false
        keyHandler.forceActiveFocus()
    }
    onClosed: { var w = parent ? parent.Window.window : null; if (w) w.advancedOpen = false }

    background: Rectangle {
        radius: 20
        color: Theme.bgCard
        border.color: Theme.surface
        border.width: 1
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.5) }

    contentItem: ColumnLayout {
        spacing: 0

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
                        root._section = (root._section + 1) % 4
                        root._focusedOption = 0
                        root._updateOptionFocus()
                    } else if (event.key === Qt.Key_Backtab) {
                        root._doneFocused = false
                        root._section = (root._section + 3) % 4
                        root._focusedOption = 0
                        root._updateOptionFocus()
                    }
                    // Down / Left / Right on Done: no-op
                    event.accepted = true
                    return
                }

                // ── Normal option navigation ───────────────────────────────────
                if (event.key === Qt.Key_Tab) {
                    root._section = (root._section + 1) % 4
                    root._focusedOption = 0
                    root._updateOptionFocus()
                    event.accepted = true

                } else if (event.key === Qt.Key_Backtab) {
                    root._section = (root._section + 3) % 4
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
                        var langs = controller.availableLanguages
                        var idx = 0
                        for (var i = 0; i < langs.length; i++)
                            if (langs[i].code === controller.language) { idx = i; break }
                        controller.setLanguage(langs[(idx + d + langs.length) % langs.length].code)

                    } else if (root._isOptionFocused(2, 0)) {
                        controller.setHudSize(
                            Math.max(50, Math.min(200, controller.hudSize + d * 10)))

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
                    model: [qsTr("General"), qsTr("Controls"), qsTr("HUD"), qsTr("Remote")]
                    delegate: Rectangle {
                        height: parent.height
                        width: (parent.width - 3 * spacing) / 4
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

            // ── General ───────────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Option 0: Transition Duration ──────────────────────────
                    Item {
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

                    // Option 1: Language ─────────────────────────────────────
                    Item {
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
                                    text: qsTr("LANGUAGE")
                                    color: root._isOptionFocused(0, 1)
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
                }
            }

            // ── Controls ──────────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Option 0: Mouse navigation ──────────────────────────────
                    Item {
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
            }

            // ── HUD ───────────────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Option 0: HUD Size ──────────────────────────────────────
                    Item {
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
                                Text { text: qsTr("Size"); color: Theme.textPrimary; font.pixelSize: 14 }
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
                }
            }

            // ── Remote ────────────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Option 0: Enable ────────────────────────────────────────
                    Item {
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
                                                root._section = (root._section + 1) % 4
                                                root._focusedOption = 0
                                                event.accepted = true
                                                Qt.callLater(keyHandler.forceActiveFocus)

                                            } else if (event.key === Qt.Key_Backtab) {
                                                root._section = (root._section + 3) % 4
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
