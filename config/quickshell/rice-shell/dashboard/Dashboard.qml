pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../island"
import "."

PanelWindow {
    id: dashboardWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Input mask: only intercepts pointer events when open/visible
    mask: Region {
        item: dashboardWindow.visible ? scrim : null
    }

    property string currentTab: "Home"
    property bool expanded: false

    function toggle(tab): void {
        var target = (tab && tab.length > 0) ? tab : "Home";
        if (!visible) {
            currentTab = target;
            closeTimer.stop();
            expanded = false;
            visible = true;
            openTimer.restart();
        } else if (currentTab !== target) {
            currentTab = target;
        } else {
            dismiss();
        }
    }

    function dismiss(): void {
        if (!visible) return;
        expanded = false;
        closeTimer.restart();
    }

    Timer {
        id: openTimer
        interval: 16
        repeat: false
        onTriggered: {
            dashboardWindow.expanded = true;
        }
    }

    Timer {
        id: closeTimer
        interval: 300
        repeat: false
        onTriggered: {
            dashboardWindow.visible = false;
        }
    }

    // Escape Key Handler to dismiss
    Item {
        focus: dashboardWindow.visible
        Keys.onEscapePressed: (event) => {
            dashboardWindow.dismiss();
            event.accepted = true;
        }
    }

    // Fullscreen Backdrop Scrim with Outside Click Dismissal
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.3)
        opacity: dashboardWindow.expanded ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        TapHandler {
            onTapped: (eventPoint) => {
                var p = eventPoint.position;
                var minX = morphContainer.x;
                var maxX = morphContainer.x + morphContainer.width;
                var minY = morphContainer.y;
                var maxY = morphContainer.y + morphShape.pillHeight;
                if (p.x < minX || p.x > maxX || p.y < minY || p.y > maxY) {
                    dashboardWindow.dismiss();
                }
            }
        }

        // Morphing Control Center Container floating below top bar
        Item {
            id: morphContainer
            anchors.top: parent.top
            anchors.topMargin: dashboardWindow.expanded ? 42 : 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: morphShape.width
            height: morphShape.height

            Behavior on anchors.topMargin {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
            }

            // Absorb inner clicks so they never trigger outside-click dismissal
            TapHandler {
                gesturePolicy: TapHandler.WithinBounds
                onTapped: (eventPoint) => {}
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            // Morphing Island Shape with rounded corners on all sides ("bo tròn vào")
            IslandShape {
                id: morphShape
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth: dashboardWindow.expanded ? 760 : 200
                pillHeight: dashboardWindow.expanded ? 440 : 0
                antiCornerRadius: 0
                bottomRadius: 22
                animDurationWidth: 280
                animDurationHeight: 300
                overshoot: 0.15
                fillColor: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.panelOpacity)
                borderColor: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.45)
                showAntiCorners: false
            }

            // Dashboard Content Layout
            Item {
                id: cardContent
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: morphShape.pillWidth
                height: morphShape.pillHeight
                clip: true
                y: dashboardWindow.expanded ? 0 : -30
                opacity: dashboardWindow.expanded ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 10
                    anchors.bottomMargin: 14
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 12

                    // Header: Branding, Tabs, and Dismiss Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Left Branding / Title
                        Row {
                            spacing: 8
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                width: 26
                                height: 26
                                radius: 13
                                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰍹"
                                    font.pixelSize: 14
                                    color: Tokens.accent
                                }
                            }

                            Text {
                                text: "Control Center"
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Center Tab Navigation Pills
                        Row {
                            spacing: 6
                            Layout.alignment: Qt.AlignHCenter

                            Repeater {
                                model: [
                                    { id: "Home", name: "Home", icon: "󰋜" },
                                    { id: "System", name: "System", icon: "󰍹" },
                                    { id: "Config", name: "Config", icon: "󰒓" }
                                ]

                                Rectangle {
                                    id: tabPill
                                    required property var modelData
                                    readonly property bool isSelected: dashboardWindow.currentTab === modelData.id

                                    width: tabRow.implicitWidth + 24
                                    height: 30
                                    radius: 15
                                    color: isSelected ? Tokens.accent : (tabHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8) : "transparent")
                                    border.color: isSelected ? "transparent" : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                                    border.width: isSelected ? 0 : 1

                                    Row {
                                        id: tabRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: tabPill.modelData.icon
                                            font.pixelSize: 12
                                            color: tabPill.isSelected ? Tokens.on_accent : Tokens.text_primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: tabPill.modelData.name
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: tabPill.isSelected ? Tokens.on_accent : Tokens.text_primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    HoverHandler { id: tabHover }
                                    TapHandler {
                                        onTapped: dashboardWindow.currentTab = tabPill.modelData.id
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Right Close Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: closeHover.hovered ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.2) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.6)
                            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.pixelSize: 14
                                color: closeHover.hovered ? Tokens.danger : Tokens.text_secondary
                            }

                            HoverHandler { id: closeHover }
                            TapHandler {
                                onTapped: dashboardWindow.dismiss()
                            }
                        }
                    }

                    // Tab View Body with Lazy Loading
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Home {
                            anchors.fill: parent
                            visible: dashboardWindow.currentTab === "Home"
                        }

                        Loader {
                            anchors.fill: parent
                            active: dashboardWindow.visible && dashboardWindow.currentTab === "System"
                            visible: dashboardWindow.currentTab === "System"
                            sourceComponent: System {}
                        }

                        Loader {
                            anchors.fill: parent
                            active: dashboardWindow.visible && dashboardWindow.currentTab === "Config"
                            visible: dashboardWindow.currentTab === "Config"
                            sourceComponent: Config {}
                        }
                    }
                }
            }
        }
    }
}
