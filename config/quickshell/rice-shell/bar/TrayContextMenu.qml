pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"

PopupWindow {
    id: root

    property var anchorWindow: null
    property var menuHandle: null
    property real clickX: 0
    property real clickY: 0
    property var menuPath: []
    readonly property var currentMenu: menuPath.length
        ? menuPath[menuPath.length - 1]
        : menuHandle
    onMenuPathChanged: menuFlickable.contentY = 0

    color: "transparent"
    visible: false
    grabFocus: true
    implicitWidth: 244
    implicitHeight: Math.min(menuList.implicitHeight + 16, 520)

    onVisibleChanged: {
        if (!visible) {
            menuHandle = null;
            menuPath = [];
        }
    }

    anchor {
        window: root.anchorWindow
        rect.x: root.anchorWindow
            ? Math.max(8, Math.min(root.clickX, root.anchorWindow.width - root.width - 8))
            : 8
        rect.y: Math.max(8, root.clickY + 6)
        rect.width: 1
        rect.height: 1
    }

    function openMenu(menu, x, y) {
        if (!menu || !anchorWindow) {
            closeMenu();
            return;
        }
        menuHandle = menu;
        menuPath = [];
        clickX = x;
        clickY = y;
        visible = true;
    }

    function closeMenu() {
        visible = false;
        menuHandle = null;
        menuPath = [];
    }

    QsMenuOpener {
        id: menuOpener
        menu: root.currentMenu
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closeMenu()
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(Tokens.surface_low.r, Tokens.surface_low.g, Tokens.surface_low.b, Tokens.panelOpacity)
        border.width: 1
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.78)

        Flickable {
            id: menuFlickable
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: menuList.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: menuList
                width: parent.width
                spacing: 2

                Item {
                    width: menuList.width
                    height: root.menuPath.length ? 32 : 0
                    visible: root.menuPath.length > 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "‹"
                            color: Tokens.accent
                            font.pixelSize: 21
                            Layout.preferredWidth: 16
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            text: root.menuPath.length
                                ? root.menuPath[root.menuPath.length - 1].text
                                : ""
                            color: Tokens.text_secondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.menuPath = root.menuPath.slice(0, -1)
                    }
                }

                Repeater {
                    model: menuOpener.children

                    delegate: Item {
                        id: menuRow
                        required property var modelData

                        width: menuList.width
                        height: modelData.isSeparator ? 10 : 34
                        opacity: modelData.isSeparator || modelData.enabled ? 1 : 0.5

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            radius: 8
                            color: rowHover.hovered
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.13)
                                : "transparent"
                            border.width: rowHover.hovered ? 1 : 0
                            border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.28)
                            visible: !menuRow.modelData.isSeparator
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            width: parent.width - 16
                            height: 1
                            color: Tokens.outline
                            opacity: 0.55
                            visible: menuRow.modelData.isSeparator
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 9
                            visible: !menuRow.modelData.isSeparator

                            Item {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18

                                Image {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    source: menuRow.modelData.icon || ""
                                    visible: Boolean(menuRow.modelData.icon)
                                    fillMode: Image.PreserveAspectFit
                                }
                            }

                            Text {
                                text: menuRow.modelData.text
                                color: menuRow.modelData.enabled ? Tokens.text_primary : Tokens.text_secondary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                Layout.fillWidth: true
                            }

                            Text {
                                text: menuRow.modelData.hasChildren
                                    ? "›"
                                    : menuRow.modelData.checkState === Qt.Checked ? "✓" : ""
                                color: Tokens.accent
                                font.pixelSize: 17
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 14
                            }
                        }

                        HoverHandler {
                            id: rowHover
                            enabled: menuRow.modelData.enabled && !menuRow.modelData.isSeparator
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            enabled: menuRow.modelData.enabled && !menuRow.modelData.isSeparator
                            onTapped: {
                                if (menuRow.modelData.hasChildren) {
                                    root.menuPath = root.menuPath.concat([menuRow.modelData]);
                                } else {
                                    menuRow.modelData.triggered();
                                    root.closeMenu();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
