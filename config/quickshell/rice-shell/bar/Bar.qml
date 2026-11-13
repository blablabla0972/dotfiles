pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import "../theme"
import "../services"

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

    readonly property string internetStatusText: {
        switch (Networking.connectivity) {
        case NetworkConnectivity.Full: return "Online";
        case NetworkConnectivity.Limited: return "Limited";
        case NetworkConnectivity.Portal: return "Portal";
        case NetworkConnectivity.None: return "Offline";
        default: return "Unknown";
        }
    }
    readonly property color internetStatusColor: Networking.connectivity === NetworkConnectivity.Full
        ? Tokens.accent
        : Tokens.text_secondary

    Component.onCompleted: {
        if (Networking.canCheckConnectivity) Networking.checkConnectivity();
    }

    // 1. Left Floating Island: App Launcher & Workspaces
    Rectangle {
        id: leftIsland
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        implicitWidth: leftLayout.implicitWidth + 20
        radius: 12
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        RowLayout {
            id: leftLayout
            anchors.centerIn: parent
            spacing: 8

            // App Launcher Icon Button
            Rectangle {
                width: 24
                height: 24
                radius: 6
                color: launcherHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰣇"
                    font.pixelSize: 14
                    color: Tokens.accent
                }

                HoverHandler { id: launcherHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestLauncher()
                }
            }

            // Divider line
            Rectangle {
                width: 1
                height: 14
                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
            }

            // Workspaces Module
            Workspaces {
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // 2. Right Floating Island: Status Tray & Clock Pill
    Rectangle {
        id: rightIsland
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        implicitWidth: rightLayout.implicitWidth + 20
        radius: 12
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        RowLayout {
            id: rightLayout
            anchors.centerIn: parent
            spacing: 8

            // Status Tray
            StatusTray {
                Layout.alignment: Qt.AlignVCenter
                parentWindow: barRoot
            }

            // Internet connectivity
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                height: 24
                implicitWidth: internetContent.implicitWidth + 14
                radius: 8
                color: internetHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    id: internetContent
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: Networking.connectivity === NetworkConnectivity.Full ? "󰤨" : "󰤮"
                        font.pixelSize: 12
                        color: barRoot.internetStatusColor
                    }

                    Text {
                        text: barRoot.internetStatusText
                        font.pixelSize: 10
                        font.bold: true
                        color: barRoot.internetStatusColor
                    }
                }

                HoverHandler { id: internetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestDashboard("Home")
                }
            }

            // Divider between network status and clock
            Rectangle {
                width: 1
                height: 14
                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
            }

            // Clock Pill
            Rectangle {
                id: clockPill
                height: 24
                implicitWidth: clockContent.implicitWidth + 14
                radius: 8
                color: clockHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                Behavior on color { ColorAnimation { duration: 150 } }

                SystemClock {
                    id: minuteClock
                    precision: SystemClock.Minutes
                }

                RowLayout {
                    id: clockContent
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "󰥔"
                        font.pixelSize: 11
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_secondary
                    }

                    Text {
                        id: clockText
                        text: Qt.formatDateTime(minuteClock.date, "hh:mm")
                        font.pixelSize: 12
                        font.bold: true
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_primary
                    }
                }

                HoverHandler { id: clockHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestDashboard("Home")
                }

            }
        }
    }
}
