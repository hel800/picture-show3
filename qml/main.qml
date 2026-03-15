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

        // Soft cross-fade between pages
        pushEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutQuad }
        }
        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
        }
        popEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutQuad }
        }
        popExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
        }

        initialItem: settingsComp
    }

    // ── Pages ─────────────────────────────────────────────────────────────────
    Component {
        id: settingsComp
        SettingsPage {
            Component.onCompleted: {
                forceActiveFocus()
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
                stack.pop()
            }
        }
    }
}
