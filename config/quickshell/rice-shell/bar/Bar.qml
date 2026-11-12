pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"

PanelWindow {
    id: barRoot

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    implicitHeight: 40

    signal requestLauncher()
    signal requestDashboard(string tab)

    anchors {
        top: true
        left: true
        right: true
    }

    exclusiveZone: 40
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Top Bar Main Frame
    Rectangle {
        id: barBackground
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: 12
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // Left Area: Workspaces & Launcher
            RowLayout {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: 10

                // Launcher icon button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 7
                    color: launcherHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰣇"
                        font.pixelSize: 15
                        color: Tokens.accent
                    }

                    HoverHandler { id: launcherHover }
                    TapHandler {
                        onTapped: barRoot.requestLauncher()
                    }
                }

                // Workspaces Module
                Workspaces {
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // Center: Reserved empty space for Dynamic Island
            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 260
            }

            // Right Area: System Tray, Status & Clock Pill
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 8

                // Status Tray
                StatusTray {
                    Layout.alignment: Qt.AlignVCenter
                }

                // Clock Pill
                Rectangle {
                    id: clockPill
                    height: 24
                    implicitWidth: clockText.implicitWidth + 16
                    radius: 8
                    color: clockHover.hovered
                        ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25)
                        : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)

                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(new Date(), "hh:mm")
                        font.pixelSize: 12
                        font.bold: true
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_primary
                    }

                    HoverHandler { id: clockHover }
                    TapHandler {
                        onTapped: barRoot.requestDashboard("Home")
                    }

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm")
                    }
                }
            }
        }
    }
}
