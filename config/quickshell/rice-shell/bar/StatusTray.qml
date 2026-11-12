pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../theme"

Row {
    id: root
    spacing: 6

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItemDelegate
            required property SystemTrayItem modelData

            width: 20
            height: 20

            Image {
                id: trayIcon
                anchors.centerIn: parent
                width: 16
                height: 16
                source: trayItemDelegate.modelData.icon || ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }

            HoverHandler { id: trayHover }

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (event) => {
                    if (event.button === Qt.RightButton && trayItemDelegate.modelData.hasMenu) {
                        trayItemDelegate.modelData.secondaryActivate();
                    } else {
                        trayItemDelegate.modelData.activate();
                    }
                }
            }
        }
    }
}
