pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"
import "IslandState.js" as IslandState

PanelWindow {
    id: islandWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: activeMode !== IslandState.State.IDLE
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
        item: (islandWindow.visible && islandWindow.activeMode !== IslandState.State.IDLE) ? islandShape : null
    }

    signal requestDashboard(string tab)

    // State properties
    property string activeMode: "idle"
    property var activeAlert: null
    property bool isHovered: hoverHandler.hovered
    property bool isPinned: false

    // Media bindings from native Mpris service
    readonly property bool hasMedia: Media.hasPlayer && Media.isPlaying
    readonly property string mediaTitle: Media.trackTitle
    readonly property string mediaArtist: Media.trackArtist

    // OSD parameters
    property real osdProgress: Audio.volume
    property string osdIcon: Audio.muted ? "󰝟" : "󰕾"

    // Synchronize dimensions based on active mode
    readonly property var currentDims: IslandState.targetDimensions(activeMode, activeAlert)

    function updateMode(): void {
        activeMode = IslandState.resolveState(activeAlert, hasMedia, isHovered, isPinned);
    }

    onIsHoveredChanged: updateMode()
    onHasMediaChanged: updateMode()
    onIsPinnedChanged: updateMode()
    onActiveAlertChanged: updateMode()

    // Listen to reactive audio events
    Connections {
        target: Audio
        function onOsdRequested(icon: string, progress: real): void {
            islandWindow.triggerOsd(icon, progress);
        }
    }

    function triggerOsd(icon: string, progress: real): void {
        osdIcon = icon;
        osdProgress = Math.max(0, Math.min(1, progress));
        activeAlert = { type: IslandState.State.OSD };
        updateMode();
        dismissTimer.restart();
    }

    function triggerNotification(summary: string, body: string, icon: string): void {
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
                    islandWindow.updateMode();
                } else if (islandWindow.activeMode === IslandState.State.MEDIA || islandWindow.activeMode === IslandState.State.IDLE) {
                    islandWindow.requestDashboard("Home");
                } else {
                    islandWindow.requestDashboard("Home");
                }
            }
        }

        // Inner Content Layer
        Item {
            anchors.fill: parent

            // 1. Media Mini Pill Content
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

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Media.isPlaying ? "󰏤" : "󰐊"
                        font.pixelSize: 12
                        color: Tokens.text_secondary
                    }

                    TapHandler {
                        onTapped: Media.togglePlaying()
                    }
                }
            }

            // 2. OSD Volume/Brightness Content (Refined & Modernized)
            RowLayout {
                visible: islandWindow.activeMode === IslandState.State.OSD
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                // Prominent Audio Glyph
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: islandWindow.osdIcon
                    font.pixelSize: 18
                    color: Tokens.accent
                }

                // Volume Progress Track
                Rectangle {
                    Layout.fillWidth: true
                    height: 10
                    radius: 5
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: Math.min(parent.width, Math.max(parent.height, parent.width * islandWindow.osdProgress))
                        radius: 5
                        color: Tokens.accent

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // Value Percentage Text with Tabular Digits
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(islandWindow.osdProgress * 100) + "%"
                    font.pixelSize: 12
                    font.bold: true
                    font.features: { "tnum": 1 }
                    color: Tokens.text_primary
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

                // Playback control buttons
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 28

                    Rectangle {
                        width: 24; height: 24; radius: 12; color: "transparent"
                        Text { anchors.centerIn: parent; text: "󰒮"; font.pixelSize: 16; color: Tokens.text_secondary }
                        TapHandler { onTapped: Media.previous() }
                    }

                    Rectangle {
                        width: 32; height: 32; radius: 16; color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                        Text { anchors.centerIn: parent; text: Media.isPlaying ? "󰏤" : "󰐊"; font.pixelSize: 18; color: Tokens.accent }
                        TapHandler { onTapped: Media.togglePlaying() }
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12; color: "transparent"
                        Text { anchors.centerIn: parent; text: "󰒭"; font.pixelSize: 16; color: Tokens.text_secondary }
                        TapHandler { onTapped: Media.next() }
                    }
                }
            }
        }
    }
}
