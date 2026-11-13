pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../theme"

Row {
    id: root
    required property var parentWindow
    spacing: 6

    TrayContextMenu {
        id: trayContextMenu
        anchorWindow: root.parentWindow
    }

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItemDelegate
            required property SystemTrayItem modelData

            width: 24
            height: 24

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: trayHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                    : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Image {
                id: trayIcon
                anchors.centerIn: parent
                width: 18
                height: 18
                source: trayItemDelegate.modelData.icon || ""
                sourceSize.width: 36
                sourceSize.height: 36
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }

            HoverHandler { id: trayHover; cursorShape: Qt.PointingHandCursor }

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onTapped: (eventPoint, button) => {
                    if (button === Qt.LeftButton) {
                        if (trayItemDelegate.modelData.onlyMenu) {
                            if (trayItemDelegate.modelData.hasMenu) {
                                trayContextMenu.openMenu(
                                    trayItemDelegate.modelData.menu,
                                    Math.round(eventPoint.scenePosition.x),
                                    Math.round(eventPoint.scenePosition.y)
                                );
                            }
                        } else {
                            trayItemDelegate.modelData.activate();
                        }
                    } else if (button === Qt.MiddleButton) {
                        trayItemDelegate.modelData.secondaryActivate();
                    } else if (button === Qt.RightButton && trayItemDelegate.modelData.hasMenu) {
                        trayContextMenu.openMenu(
                            trayItemDelegate.modelData.menu,
                            Math.round(eventPoint.scenePosition.x),
                            Math.round(eventPoint.scenePosition.y)
                        );
                    }
                }
            }
        }
    }
}
