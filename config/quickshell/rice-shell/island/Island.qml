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
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isPinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Input Region: only intercepts clicks on islandShape (when OSD) or scrim (when pinned/expanded)
    mask: Region {
        item: (islandWindow.visible && islandWindow.activeMode !== IslandState.State.IDLE)
            ? (islandWindow.isPinned ? scrim : islandShape)
            : null
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

    // Escape Key Handler to collapse expanded media capsule
    Item {
        focus: islandWindow.isPinned
        Keys.onEscapePressed: (event) => {
            islandWindow.isPinned = false;
            islandWindow.updateMode();
            event.accepted = true;
        }
    }

    // Backdrop Scrim for Outside-Click Dismissal when pinned/expanded
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"

        TapHandler {
            enabled: islandWindow.isPinned
            onTapped: (eventPoint) => {
                var p = eventPoint.position;
                var minX = islandContainer.x;
                var maxX = islandContainer.x + islandContainer.width;
                var minY = islandContainer.y;
                var maxY = islandContainer.y + islandShape.pillHeight;
                if (p.x < minX || p.x > maxX || p.y < minY || p.y > maxY) {
                    islandWindow.isPinned = false;
                    islandWindow.updateMode();
                }
            }
        }

        // Centered Morphing Island Container floating below top bar when expanded
        Item {
            id: islandContainer
            anchors.top: parent.top
            anchors.topMargin: islandWindow.isPinned ? 42 : 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: islandShape.width
            height: islandShape.height

            Behavior on anchors.topMargin {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            IslandShape {
                id: islandShape
                anchors.centerIn: parent
                pillWidth: islandWindow.currentDims.width
                pillHeight: islandWindow.currentDims.height
                bottomRadius: islandWindow.currentDims.radius
                fillColor: Tokens.surface
                borderColor: Tokens.outline
                showAntiCorners: !islandWindow.isPinned
            }

            HoverHandler {
                id: hoverHandler
            }

            TapHandler {
                gesturePolicy: TapHandler.WithinBounds
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

            // 5. Expanded Media Capsule Content
            Item {
                id: expandedMediaContent
                visible: islandWindow.activeMode === IslandState.State.EXPANDED
                anchors.fill: parent
                anchors.margins: 12

                // Waveform phase oscillation timer (inspired by Tide-island & DynamicGlacier)
                Timer {
                    interval: 64
                    repeat: true
                    running: expandedMediaContent.visible && Media.isPlaying
                    onTriggered: {
                        expandedMediaContent.visualizerPhase += 0.18;
                        if (expandedMediaContent.visualizerPhase > Math.PI * 2) {
                            expandedMediaContent.visualizerPhase -= Math.PI * 2;
                        }
                    }
                }

                property real visualizerPhase: 0
                function visualizerLevel(index) {
                    var phase = visualizerPhase + index * 0.78;
                    var primary = (Math.sin(phase) + 1) * 0.5;
                    var secondary = (Math.sin(phase * 2 + index * 0.95) + 1) * 0.5;
                    return 0.22 + primary * 0.42 + secondary * 0.24;
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    // Tier 1: Track Header (Artwork 50x50, Title/Artist, 5-bar Waveform)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        spacing: 12

                        // Album artwork 50x50 (radius 10)
                        Rectangle {
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 50
                            radius: 10
                            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: Media.trackArtUrl
                                fillMode: Image.PreserveAspectCrop
                                visible: Media.hasPlayer && Media.trackArtUrl.length > 0 && status === Image.Ready
                                asynchronous: true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰎆"
                                font.pixelSize: 22
                                color: Tokens.accent
                                visible: !(Media.hasPlayer && Media.trackArtUrl.length > 0)
                            }
                        }

                        // Track Title & Artist
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: Media.trackTitle.length > 0 ? Media.trackTitle : "No Media Playing"
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Media.trackArtist.length > 0 ? Media.trackArtist : "Active Audio Stream"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: Tokens.text_secondary
                                elide: Text.ElideRight
                            }
                        }

                        // Mini 5-bar Waveform Visualizer
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3
                            height: 22

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: 3
                                    height: Media.isPlaying 
                                        ? 4 + 18 * expandedMediaContent.visualizerLevel(index) 
                                        : 5
                                    radius: 1.5
                                    color: Media.isPlaying ? Tokens.accent : Tokens.text_secondary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on height {
                                        NumberAnimation { duration: 110; easing.type: Easing.InOutQuad }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }
                            }
                        }
                    }

                    // Tier 2: Seek Bar & Timers
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: Media.formatTime(Media.position)
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Tokens.text_secondary
                        }

                        Rectangle {
                            id: progressBarTrack
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                            clip: true

                            Rectangle {
                                height: parent.height
                                width: Math.min(parent.width, Math.max(0, parent.width * Media.progress))
                                radius: 2
                                color: Tokens.accent

                                Behavior on width {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (Media.length > 0) {
                                        var ratio = Math.max(0.0, Math.min(1.0, mouse.x / progressBarTrack.width));
                                        Media.setPosition(ratio * Media.length);
                                    }
                                }
                            }
                        }

                        Text {
                            text: Media.length > 0 ? Media.formatTime(Media.length) : "--:--"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Tokens.text_secondary
                        }
                    }

                    // Tier 3: Controls (Previous, Play/Pause, Next)
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 32

                        Rectangle {
                            width: 28; height: 28; radius: 14; color: prevHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰒮"; font.pixelSize: 16; color: prevHover.hovered ? Tokens.accent : Tokens.text_secondary }
                            HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Media.previous() }
                        }

                        Rectangle {
                            width: 34; height: 34; radius: 17; color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, playHover.hovered ? 0.35 : 0.22)
                            border.color: Tokens.accent; border.width: 1
                            Text { anchors.centerIn: parent; text: Media.isPlaying ? "󰏤" : "󰐊"; font.pixelSize: 17; color: Tokens.accent }
                            HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Media.togglePlaying() }
                        }

                        Rectangle {
                            width: 28; height: 28; radius: 14; color: nextHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰒭"; font.pixelSize: 16; color: nextHover.hovered ? Tokens.accent : Tokens.text_secondary }
                            HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Media.next() }
                        }
                    }
                }
            }
        }
    }
}
}
