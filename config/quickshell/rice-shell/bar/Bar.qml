pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"

PanelWindow {
    id: barRoot

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    implicitHeight: 40

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
                spacing: 6

                // Launcher icon button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: launcherHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰣇"
                        font.pixelSize: 15
                        color: Tokens.accent
                    }

                    HoverHandler { id: launcherHover }
                    TapHandler {
                        onTapped: {
                            // Will trigger launcher toggle
                        }
                    }
                }

                // Workspaces pill
                Row {
                    spacing: 4

                    Repeater {
                        model: 5

                        Rectangle {
                            required property int index
                            readonly property int wsId: index + 1
                            readonly property bool isCurrent: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId

                            width: isCurrent ? 24 : 8
                            height: 8
                            radius: 4
                            color: isCurrent ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)

                            Behavior on width {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            TapHandler {
                                onTapped: Hyprland.dispatch("workspace " + wsId)
                            }
                        }
                    }
                }
            }

            // Center: Flexible spacer to allow Island centering
            Item {
                Layout.fillWidth: true
            }

            // Right Area: Clock Pill
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 8

                Rectangle {
                    height: 24
                    implicitWidth: clockText.implicitWidth + 16
                    radius: 8
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)

                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(new Date(), "hh:mm")
                        font.pixelSize: 12
                        font.bold: true
                        color: Tokens.text_primary
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
