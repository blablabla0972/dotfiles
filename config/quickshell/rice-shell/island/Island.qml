pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "IslandState.js" as IslandState

PanelWindow {
    id: islandWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    implicitHeight: Math.max(48, islandShape.height + 8)

    anchors {
        top: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Input Region: only the visible island shape intercepts clicks
    mask: Region {
        item: islandShape
    }

    // State properties
    property string activeMode: "idle"
    property var activeAlert: null
    property bool isHovered: hoverHandler.hovered
    property bool isPinned: false
    property bool hasMedia: false
    property string mediaTitle: "No Track Playing"
    property string mediaArtist: ""
    property real osdProgress: 0.5
    property string osdIcon: "󰕾"

    // Synchronize dimensions based on active mode
    readonly property var currentDims: IslandState.targetDimensions(activeMode, activeAlert)

    function updateMode(): void {
        activeMode = IslandState.resolveState(activeAlert, hasMedia, isHovered, isPinned);
    }

    onIsHoveredChanged: updateMode()
    onHasMediaChanged: updateMode()
    onIsPinnedChanged: updateMode()
    onActiveAlertChanged: updateMode()

    function triggerOsd(icon, progress): void {
        osdIcon = icon;
        osdProgress = Math.max(0, Math.min(1, progress));
        activeAlert = { type: IslandState.State.OSD };
        updateMode();
        dismissTimer.restart();
    }

    function triggerNotification(summary, body, icon): void {
        activeAlert = {
            type: IslandState.State.NOTIFICATION,
            summary: summary,
            body: body,
            icon: icon
        };
        updateMode();
        dismissTimer.interval = 4000;
        dismissTimer.restart();
    }

    Timer {
        id: dismissTimer
        interval: 2200
        repeat: false
        onTriggered: {
            islandWindow.activeAlert = null;
            islandWindow.updateMode();
        }
    }

    // Centered Morphing Island Container
    Item {
        id: islandContainer
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: islandShape.width
        height: islandShape.height

        IslandShape {
            id: islandShape
            anchors.centerIn: parent
            pillWidth: islandWindow.currentDims.width
            pillHeight: islandWindow.currentDims.height
            bottomRadius: islandWindow.currentDims.radius
            fillColor: Tokens.surface
            borderColor: Tokens.outline
            showAntiCorners: true
        }

        HoverHandler {
            id: hoverHandler
        }

        TapHandler {
            onTapped: {
                if (islandWindow.activeMode === IslandState.State.EXPANDED) {
                    islandWindow.isPinned = false;
                } else if (islandWindow.activeMode === IslandState.State.MEDIA || islandWindow.hasMedia) {
                    islandWindow.isPinned = true;
                }
                islandWindow.updateMode();
            }
        }

        // Inner Content Layer
        Item {
            anchors.fill: parent
            clip: true

            // 1. Idle Content
            Row {
                visible: islandWindow.activeMode === IslandState.State.IDLE
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Tokens.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Dynamic Island"
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // 2. Media Mini Pill Content
            RowLayout {
                visible: islandWindow.activeMode === IslandState.State.MEDIA
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Text {
                    text: "󰎆"
                    font.pixelSize: 13
                    color: Tokens.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: islandWindow.mediaTitle
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_primary
                    elide: Text.ElideRight
                }

                Text {
                    text: "󰏤"
                    font.pixelSize: 12
                    color: Tokens.text_secondary
                }
            }

            // 3. OSD Volume/Brightness Content
            RowLayout {
                visible: islandWindow.activeMode === IslandState.State.OSD
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8

                Text {
                    text: islandWindow.osdIcon
                    font.pixelSize: 14
                    color: Tokens.accent
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)

                    Rectangle {
                        height: parent.height
                        width: parent.width * islandWindow.osdProgress
                        radius: 3
                        color: Tokens.accent
                    }
                }
            }

            // 4. Notification Alert Content
            RowLayout {
                visible: islandWindow.activeMode === IslandState.State.NOTIFICATION
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.pixelSize: 16
                        color: Tokens.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: islandWindow.activeAlert ? (islandWindow.activeAlert.summary || "Notification") : ""
                        font.pixelSize: 12
                        font.bold: true
                        color: Tokens.text_primary
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: islandWindow.activeAlert ? (islandWindow.activeAlert.body || "") : ""
                        font.pixelSize: 11
                        color: Tokens.text_secondary
                        elide: Text.ElideRight
                    }
                }
            }

            // 5. Expanded Media / Control Content
            ColumnLayout {
                visible: islandWindow.activeMode === IslandState.State.EXPANDED
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 42
                        height: 42
                        radius: 10
                        color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)

                        Text {
                            anchors.centerIn: parent
                            text: "󰎆"
                            font.pixelSize: 20
                            color: Tokens.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: islandWindow.mediaTitle
                            font.pixelSize: 13
                            font.bold: true
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: islandWindow.mediaArtist.length > 0 ? islandWindow.mediaArtist : "Active Audio Stream"
                            font.pixelSize: 11
                            color: Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }
                }

                // Mini control bar
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24

                    Text { text: "󰒮"; font.pixelSize: 16; color: Tokens.text_secondary }
                    Text { text: "󰐊"; font.pixelSize: 20; color: Tokens.accent }
                    Text { text: "󰒭"; font.pixelSize: 16; color: Tokens.text_secondary }
                }
            }
        }
    }
}
