pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
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

    property bool islandActive: false

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

    // 2. Center Floating Island: Inline Dynamic Island
    Rectangle {
        id: centerIsland
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        implicitWidth: centerContent.implicitWidth + 24
        radius: 14
        color: centerHover.hovered 
            ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, Tokens.barOpacity) 
            : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: centerHover.hovered 
            ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.5)
            : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        opacity: barRoot.islandActive ? 0.0 : 1.0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on implicitWidth {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        HoverHandler { id: centerHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: barRoot.requestDashboard("Home")
        }

        RowLayout {
            id: centerContent
            anchors.centerIn: parent
            spacing: 8

            // Media Active State
            RowLayout {
                visible: Media.hasPlayer && Media.isPlaying
                spacing: 8

                Text {
                    text: "󰎆"
                    font.pixelSize: 13
                    color: Tokens.accent
                }

                Text {
                    text: {
                        var str = Media.trackTitle;
                        if (Media.trackArtist && Media.trackArtist.length > 0) {
                            str += " • " + Media.trackArtist;
                        }
                        return str;
                    }
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_primary
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                }

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: mediaBtnHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Media.isPlaying ? "󰏤" : "󰐊"
                        font.pixelSize: 12
                        color: Tokens.accent
                    }

                    HoverHandler { id: mediaBtnHover }
                    TapHandler {
                        onTapped: Media.togglePlaying()
                    }
                }
            }

            // Idle State: Sleek Dynamic Island Pill
            RowLayout {
                visible: !(Media.hasPlayer && Media.isPlaying)
                spacing: 6

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                    Text {
                        anchors.centerIn: parent
                        text: "󰍹"
                        font.pixelSize: 11
                        color: Tokens.accent
                    }
                }

                Text {
                    text: "Control Center"
                    font.pixelSize: 11
                    font.bold: true
                    color: centerHover.hovered ? Tokens.accent : Tokens.text_primary

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }
        }
    }

    // 3. Right Floating Island: Status Tray & Clock Pill
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

        RowLayout {
            id: rightLayout
            anchors.centerIn: parent
            spacing: 8

            // Status Tray
            StatusTray {
                Layout.alignment: Qt.AlignVCenter
            }

            // Divider between tray and clock if tray has items
            Rectangle {
                visible: SystemTray.items.length > 0
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
                        text: Qt.formatDateTime(new Date(), "hh:mm")
                        font.pixelSize: 12
                        font.bold: true
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_primary
                    }
                }

                HoverHandler { id: clockHover; cursorShape: Qt.PointingHandCursor }
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
