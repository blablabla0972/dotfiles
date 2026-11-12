pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"

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

    // Input mask: only active when visible
    mask: Region {
        item: dashboardWindow.visible ? scrim : null
    }

    property string currentTab: "Home"

    function toggle(tab): void {
        if (tab && tab.length > 0) currentTab = tab;
        visible = !visible;
    }

    // Escape Key Handler to dismiss
    Item {
        focus: dashboardWindow.visible
        Keys.onEscapePressed: (event) => {
            dashboardWindow.visible = false;
            event.accepted = true;
        }
    }

    // Backdrop Scrim with Outside Click Dismissal
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: dashboardWindow.visible ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }

        TapHandler {
            onTapped: dashboardWindow.visible = false
        }

        // Center Modal Card
        Rectangle {
            id: dashboardCard
            anchors.centerIn: parent
            width: Math.min(960, parent.width - 32)
            height: Math.min(420, parent.height - 48)
            radius: 18
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.panelOpacity)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1

            // Absorb inner taps so they don't dismiss the modal
            TapHandler {
                // Prevent bubbling to scrim
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                // Header Tab Pills
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: ["Home", "System", "Apps", "Config"]

                        Rectangle {
                            id: tabPill
                            required property string modelData
                            readonly property bool isSelected: dashboardWindow.currentTab === modelData

                            width: tabLabel.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: isSelected ? Tokens.accent : (tabHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8) : "transparent")

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: tabPill.modelData
                                font.pixelSize: 12
                                font.bold: true
                                color: tabPill.isSelected ? Tokens.on_accent : Tokens.text_primary
                            }

                            HoverHandler { id: tabHover }
                            TapHandler {
                                onTapped: dashboardWindow.currentTab = tabPill.modelData
                            }
                        }
                    }
                }

                // Tab View Content
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // 1. Home Tab Content
                    Home {
                        anchors.centerIn: parent
                        visible: dashboardWindow.currentTab === "Home"
                    }

                    // 2. System Tab Placeholder
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: dashboardWindow.currentTab === "System"
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰍹 System Overview"
                            font.pixelSize: 22
                            color: Tokens.accent
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "CPU, Memory, and Storage telemetry"
                            font.pixelSize: 12
                            color: Tokens.text_secondary
                        }
                    }

                    // 3. Apps Tab Placeholder
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: dashboardWindow.currentTab === "Apps"
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰀻 Applications"
                            font.pixelSize: 22
                            color: Tokens.accent
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Browse installed desktop applications"
                            font.pixelSize: 12
                            color: Tokens.text_secondary
                        }
                    }

                    // 4. Config Tab Placeholder
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: dashboardWindow.currentTab === "Config"
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰒓 Configuration"
                            font.pixelSize: 22
                            color: Tokens.accent
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Desktop shell & theme preferences"
                            font.pixelSize: 12
                            color: Tokens.text_secondary
                        }
                    }
                }
            }
        }
    }
}
