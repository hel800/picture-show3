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

    // ── Page stack ────────────────────────────────────────────────────────────
    StackView {
        id: stack
        anchors.fill: parent

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

    // ── Pages ─────────────────────────────────────────────────────────────────
    Component {
        id: settingsComp
        SettingsPage {
            Component.onCompleted: {
                forceActiveFocus()
                if (controller.remoteEnabled)
                    remoteServer.start()
            }
            onStartShow: {
                controller.startShow()
                remoteServer.setShowActive(true)
                stack.push(slideshowComp)
            }
        }
    }

    Component {
        id: slideshowComp
        SlideshowPage {
            onExitShow: {
                controller.stopShow()
                remoteServer.setShowActive(false)
                var sp = stack.get(0)
                sp.hasStarted     = true
                sp._folderAtStart = controller.folder
                sp._sortAtStart   = controller.sortOrder
                stack.pop()
                sp.triggerSlideIn()
            }
        }
    }
}
