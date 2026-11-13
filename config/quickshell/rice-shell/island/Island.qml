pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"
import "../dashboard"
import "IslandState.js" as IslandState

PanelWindow {
    id: islandWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: true
    // Grow ahead of the pill animation; delay shrinking until the morph settles.
    readonly property real requestedLayerHeight: Math.ceil(Math.max(currentDims.height, islandShape.pillHeight) + 8)
    property real retainedLayerHeight: IslandState.targetDimensions(IslandState.State.IDLE).height + 8
    implicitHeight: Math.max(requestedLayerHeight, retainedLayerHeight)

    function reconcileLayerHeight(): void {
        if (isPinned || dashboardShowing) {
            layerShrinkTimer.stop();
            return;
        }
        if (requestedLayerHeight >= retainedLayerHeight) {
            layerShrinkTimer.stop();
            retainedLayerHeight = requestedLayerHeight;
        } else {
            layerShrinkTimer.restart();
        }
    }

    onRequestedLayerHeightChanged: reconcileLayerHeight()
    onDashboardShowingChanged: {
        reconcileLayerHeight();
        if (!dashboardShowing && hoverHandler.hovered && hasMedia && !activeAlert && !modalOpen)
            hoverDwell.restart();
    }
    Component.onCompleted: reconcileLayerHeight()

    Timer {
        id: layerShrinkTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!islandWindow.isPinned && !islandWindow.dashboardShowing)
                islandWindow.retainedLayerHeight = islandWindow.requestedLayerHeight;
        }
    }

    anchors {
        top: true
        bottom: islandWindow.isPinned || islandWindow.dashboardShowing
        left: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: dashboard.expanded ? WlrKeyboardFocus.Exclusive
        : (isPinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    // Match the interactive body, excluding the transparent anti-corner margins.
    mask: Region {
        item: islandWindow.modalOpen ? scrim : null
        x: islandContainer.x + islandShape.a
        y: islandContainer.y
        width: islandShape.pillWidth
        height: islandShape.pillHeight
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: islandWindow.modalOpen ? 0 : islandShape.r
        bottomRightRadius: islandWindow.modalOpen ? 0 : islandShape.r
    }

    signal requestDashboard(string tab)

    // State properties
    property string activeMode: "idle"
    property var activeAlert: null
    property bool hoverPreview: false
    property bool isPinned: false
    readonly property bool dashboardShowing: dashboard.expanded || dashboard.closing
    readonly property bool dashboardExpanded: dashboard.expanded
    readonly property string dashboardCurrentTab: dashboard.currentTab
    // Release fullscreen input when Dashboard starts closing; keep its geometry until the morph ends.
    readonly property bool modalOpen: isPinned || dashboard.expanded
    property string dashboardOriginMode: IslandState.State.IDLE
    property var dashboardOriginDims: IslandState.targetDimensions(IslandState.State.IDLE)

    function toggleDashboard(tab: string): void {
        if (!dashboardShowing) {
            dashboardOriginMode = activeMode;
            dashboardOriginDims = { width: islandShape.pillWidth, height: islandShape.pillHeight };
        }
        dashboard.toggle(tab);
    }

    function dismissDashboard(): void { dashboard.dismiss(); }

    function toggleSideDrawer(type: string): void {
        var drawer = IslandState.normalizeSideDrawer(type);
        if (!drawer) return;
        if (!dashboard.expanded || dashboard.currentTab !== "Home")
            toggleDashboard("Home");
        dashboard.toggleSideDrawer(drawer);
    }

    function finishDashboardClose(): void {
        if (dashboard.closing
            && Math.abs(islandShape.pillWidth - currentDims.width) < 0.01
            && Math.abs(islandShape.pillHeight - currentDims.height) < 0.01)
            dashboard.closing = false;
    }

    // Media bindings from native Mpris service
    readonly property bool hasMedia: Media.hasPlayer
    readonly property string mediaTitle: Media.trackTitle

    // OSD parameters
    property real osdProgress: IslandState.normalizeOsdProgress(Audio.volume, "volume")
    property string osdKind: "volume"
    readonly property real osdFill: IslandState.osdFill(osdProgress)
    property string osdIcon: Audio.muted ? "󰝟" : "󰕾"

    // Synchronize dimensions based on active mode
    readonly property var dashboardDimensions: IslandState.dashboardGeometry(
        targetScreen.width, targetScreen.height, 7)
    readonly property var currentDims: activeMode === IslandState.State.DASHBOARD
        ? dashboardDimensions : IslandState.targetDimensions(activeMode, activeAlert)
    readonly property color islandColor: Tokens.mode === "dark" ? Qt.darker(Tokens.surface, 1.65) : Tokens.surface
    function reveal(mode): real {
        if (activeMode !== mode && !(dashboard.expanded && dashboardOriginMode === mode)) return 0;
        const dims = IslandState.targetDimensions(mode);
        const delta = Math.max(Math.abs(islandShape.pillWidth - dims.width) / dims.width,
                               Math.abs(islandShape.pillHeight - dims.height) / dims.height);
        return Math.max(0, Math.min(1, 1 - delta * 2.5));
    }

    function collapse(): void {
        hoverDwell.stop();
        hoverGrace.stop();
        hoverPreview = false;
        isPinned = false;
        updateMode();
    }
    readonly property string notificationIconSource: {
        var icon = activeAlert ? (activeAlert.appIcon || "") : "";
        if (!icon) return "";
        if (icon.charAt(0) === "/" || icon.indexOf(":/") >= 0 || icon.indexOf("://") >= 0) return icon;
        return Quickshell.iconPath(icon, true);
    }

    function updateMode(): void {
        activeMode = IslandState.resolveState(activeAlert, hasMedia, hoverPreview, isPinned, dashboard.expanded);
    }

    onHoverPreviewChanged: updateMode()
    onHasMediaChanged: {
        if (!hasMedia) collapse();
        updateMode();
    }
    onIsPinnedChanged: {
        if (isPinned) {
            hoverDwell.stop();
            hoverGrace.stop();
            hoverPreview = false;
            dismissTimer.stop();
            activeAlert = null;
        }
        updateMode();
        reconcileLayerHeight();
    }
    onActiveAlertChanged: {
        if (activeAlert) {
            hoverDwell.stop();
            hoverGrace.stop();
            hoverPreview = false;
        }
        updateMode();
        if (!activeAlert && hoverHandler.hovered && hasMedia && !hoverPreview
            && !modalOpen && !dashboardShowing)
            hoverDwell.restart();
    }

    Timer {
        id: hoverDwell
        interval: 180
        onTriggered: {
            if (hoverHandler.hovered && islandWindow.hasMedia && !islandWindow.activeAlert
                && !islandWindow.modalOpen && !islandWindow.dashboardShowing)
                islandWindow.hoverPreview = true;
        }
    }
    Timer {
        id: hoverGrace
        interval: 220
        onTriggered: islandWindow.hoverPreview = false
    }

    function triggerOsd(icon: string, progress: real, kind): void {
        if (modalOpen || dashboardShowing || (activeAlert && activeAlert.type === IslandState.State.NOTIFICATION)) return;
        osdIcon = icon;
        osdKind = kind === "brightness" ? "brightness" : "volume";
        osdProgress = IslandState.normalizeOsdProgress(progress, osdKind);
        activeAlert = { type: IslandState.State.OSD };
        dismissTimer.interval = 2200;
        dismissTimer.restart();
    }

    function triggerNotification(summary: string, body: string, appName: string, appIcon: string): void {
        if (modalOpen || dashboardShowing) return;
        activeAlert = {
            type: IslandState.State.NOTIFICATION,
            summary: summary,
            body: body,
            appName: appName || "",
            appIcon: appIcon || ""
        };
        dismissTimer.interval = 4000;
        dismissTimer.restart();
    }

    Timer {
        id: dismissTimer
        interval: 2200
        repeat: false
        onTriggered: islandWindow.activeAlert = null
    }

    // Keep Escape on the media capsule; Dashboard handles keys from its own focused descendants.
    Item {
        focus: islandWindow.isPinned && !dashboard.expanded
        Keys.onEscapePressed: (event) => {
            islandWindow.collapse();
            event.accepted = true;
        }
    }

    // Backdrop Scrim for Outside-Click Dismissal when pinned/expanded
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"

        TapHandler {
            enabled: islandWindow.modalOpen
            onTapped: (eventPoint) => {
                var p = eventPoint.position;
                var minX = islandContainer.x;
                var maxX = islandContainer.x + islandContainer.width;
                var minY = islandContainer.y;
                var maxY = islandContainer.y + islandShape.pillHeight;
                if ((p.x < minX || p.x > maxX || p.y < minY || p.y > maxY)
                    && !dashboard.containsDrawer(p.x, p.y)) {
                    if (dashboard.expanded) dashboard.dismiss();
                    else islandWindow.collapse();
                }
            }
        }

        // The one surface morphs between media, alerts and Control Center.
        Item {
            id: islandContainer
            anchors.top: parent.top
            anchors.topMargin: 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -dashboard.drawerOffset
            width: islandShape.width
            height: islandShape.height

            IslandShape {
                id: islandShape
                anchors.centerIn: parent
                pillWidth: islandWindow.currentDims.width
                pillHeight: islandWindow.currentDims.height
                bottomRadius: islandWindow.currentDims.radius
                antiCornerRadius: 7
                animDurationWidth: dashboard.expanded ? 320 : dashboard.closing ? 200 : islandWindow.activeMode === IslandState.State.EXPANDED ? 340 : 270
                animDurationHeight: dashboard.expanded ? 320 : dashboard.closing ? 200 : islandWindow.activeMode === IslandState.State.EXPANDED ? 320 : 250
                onPillWidthChanged: islandWindow.finishDashboardClose()
                onPillHeightChanged: islandWindow.finishDashboardClose()
                overshoot: 0
                fillColor: islandWindow.islandColor
                borderColor: Tokens.outline
                showAntiCorners: true
                Behavior on bottomRadius {
                    NumberAnimation { duration: 270; easing.type: Easing.OutCubic }
                }
            }

            HoverHandler {
                id: hoverHandler
                onHoveredChanged: {
                    if (hovered) {
                        hoverGrace.stop();
                        if (islandWindow.activeMode === IslandState.State.MEDIA) hoverDwell.restart();
                    } else {
                        hoverDwell.stop();
                        if (islandWindow.hoverPreview) hoverGrace.restart();
                    }
                }
            }

            TapHandler {
                enabled: !islandWindow.dashboardShowing && (islandWindow.activeMode === IslandState.State.IDLE
                    || islandWindow.activeMode === IslandState.State.NOTIFICATION
                    || islandWindow.activeMode === IslandState.State.OSD)
                onTapped: islandWindow.requestDashboard("Home")
            }

            TapHandler {
                enabled: !islandWindow.dashboardShowing
                acceptedButtons: Qt.RightButton
                onTapped: {
                    islandWindow.collapse();
                    islandWindow.requestDashboard("Home");
                }
            }

            // Fixed target-size content is clipped by the animated body, not squeezed.
            Item {
                id: contentViewport
                enabled: !islandWindow.dashboardShowing
                x: islandShape.a
                width: islandShape.pillWidth
                height: islandShape.pillHeight
                clip: true

                RowLayout {
                    opacity: islandWindow.reveal(IslandState.State.IDLE)
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    visible: opacity > 0
                    enabled: opacity > 0.9
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        text: "󰍹"
                        font.pixelSize: 14
                        color: Tokens.accent
                    }
                    Text {
                        text: "Control Center"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Tokens.text_primary
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                RowLayout {
                    opacity: islandWindow.reveal(IslandState.State.MEDIA)
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    visible: opacity > 0
                    enabled: opacity > 0.9
                    anchors.centerIn: parent
                    width: IslandState.targetDimensions(IslandState.State.MEDIA).width - 24
                    height: 28
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 5
                        color: Tokens.surface_high
                        Image {
                            id: miniArtwork
                            anchors.fill: parent
                            source: Media.trackArtUrl
                            sourceSize.width: 44
                            sourceSize.height: 44
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "󰎆"
                            color: Tokens.accent
                            font.pixelSize: 13
                            visible: miniArtwork.status !== Image.Ready
                        }
                        TapHandler { onTapped: islandWindow.isPinned = true }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: islandWindow.mediaTitle
                        textFormat: Text.PlainText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Tokens.text_primary
                        elide: Text.ElideRight
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: islandWindow.isPinned = true }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Media.isPlaying ? "󰏤" : "󰐊"
                            font.pixelSize: 14
                            color: Tokens.accent
                        }
                        HoverHandler { enabled: islandWindow.hasMedia && Media.canToggle; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: islandWindow.hasMedia && Media.canToggle; onTapped: Media.togglePlaying() }
                    }
                }

            // 2. OSD Volume/Brightness Content (Refined & Modernized)
            RowLayout {
                opacity: islandWindow.reveal(IslandState.State.OSD)
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                visible: opacity > 0
                enabled: opacity > 0.9
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.OSD).width - 32
                height: 32
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
                    height: 5
                    radius: 2.5
                    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * islandWindow.osdFill
                        radius: 2.5
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

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 9
                    text: islandWindow.osdKind === "volume" && islandWindow.osdProgress > 1 ? "+" : ""
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.accent
                }
            }

            // 4. Notification Alert Content
            RowLayout {
                opacity: islandWindow.reveal(IslandState.State.NOTIFICATION)
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                visible: opacity > 0
                enabled: opacity > 0.9
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.NOTIFICATION).width - 32
                height: 64
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 12
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)

                    Image {
                        id: notificationAppIcon
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: islandWindow.notificationIconSource
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.pixelSize: 19
                        color: Tokens.accent
                        visible: notificationAppIcon.status !== Image.Ready
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: islandWindow.activeAlert
                            ? (islandWindow.activeAlert.appName || "Notification")
                            : "Notification"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Tokens.accent
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: islandWindow.activeAlert ? (islandWindow.activeAlert.summary || "Notification") : ""
                        textFormat: Text.PlainText
                        font.pixelSize: 14
                        font.bold: true
                        color: Tokens.text_primary
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumHeight: 32
                            textFormat: Text.PlainText
                        text: islandWindow.activeAlert ? (islandWindow.activeAlert.body || "") : ""
                        font.pixelSize: 12
                        color: Tokens.text_secondary
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                }
            }

            // 5. Expanded Media Capsule Content
            Item {
                id: expandedMediaContent
                opacity: islandWindow.reveal(IslandState.State.EXPANDED)
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                visible: opacity > 0
                // Enable visible controls during the final part of the reveal animation.
                enabled: islandWindow.activeMode === IslandState.State.EXPANDED && opacity > 0.5
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.EXPANDED).width - 32
                height: IslandState.targetDimensions(IslandState.State.EXPANDED).height - 28

                // Waveform phase oscillation timer (inspired by Tide-island & DynamicGlacier)
                Timer {
                    interval: 110
                    repeat: true
                    running: expandedMediaContent.visible && Media.isPlaying
                    onTriggered: {
                        expandedMediaContent.visualizerPhase += 0.18;
                        if (expandedMediaContent.visualizerPhase > Math.PI * 2) {
                            expandedMediaContent.visualizerPhase -= Math.PI * 2;
                        }
                    }
                }

                // MPRIS position is read on demand; refresh bindings while the card is visible.
                Timer {
                    interval: 1000
                    repeat: true
                    running: expandedMediaContent.visible && Media.isPlaying
                        && Media.activePlayer !== null && Media.activePlayer.positionSupported
                    onTriggered: {
                        if (Media.activePlayer && Media.isPlaying)
                            Media.activePlayer.positionChanged();
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
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: 10
                            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                            clip: true

                            Image {
                                id: expandedArtwork
                                anchors.fill: parent
                                source: islandWindow.hasMedia ? Media.trackArtUrl : ""
                                sourceSize.width: 100
                                sourceSize.height: 100
                                fillMode: Image.PreserveAspectCrop
                                visible: Media.hasPlayer && Media.trackArtUrl.length > 0 && status === Image.Ready
                                asynchronous: true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰎆"
                                font.pixelSize: 22
                                color: Tokens.accent
                                visible: expandedArtwork.status !== Image.Ready
                            }
                        }

                        // Track Title & Artist
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: islandWindow.hasMedia ? Media.trackTitle : "No media playing"
                                textFormat: Text.PlainText
                                font.pixelSize: 13
                                font.bold: true
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: islandWindow.hasMedia ? (Media.trackArtist || "Active audio stream") : "Play something to get started"
                                textFormat: Text.PlainText
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
                                    required property int index
                                    width: 3
                                    height: Media.isPlaying 
                                        ? 4 + 18 * expandedMediaContent.visualizerLevel(index) 
                                        : 5
                                    radius: 1.5
                                    color: Media.isPlaying ? Tokens.accent : Tokens.text_secondary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on height {
                                        NumberAnimation { duration: 90; easing.type: Easing.InOutQuad }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            objectName: "mediaPinButton"
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: islandWindow.isPinned ? "󰅖" : "󰐃"
                                font.pixelSize: 15
                                color: Tokens.text_secondary
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (islandWindow.isPinned) islandWindow.collapse();
                                    else islandWindow.isPinned = true;
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
                            height: 5
                            radius: 2.5
                            opacity: Media.activePlayer && Media.activePlayer.canSeek && Media.length > 0 ? 1 : 0.5
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
                                anchors.topMargin: -7
                                anchors.bottomMargin: -7
                                enabled: islandWindow.hasMedia && Media.activePlayer !== null
                                    && Media.activePlayer.canSeek && Media.length > 0
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
                            width: 32; height: 32; radius: 16; color: prevHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰒮"; font.pixelSize: 16; color: prevHover.hovered ? Tokens.accent : Tokens.text_secondary; opacity: Media.canPrev ? 1 : 0.45 }
                            HoverHandler { id: prevHover; enabled: islandWindow.hasMedia && Media.canPrev; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: islandWindow.hasMedia && Media.canPrev; onTapped: Media.previous() }
                        }

                        Rectangle {
                            width: 40; height: 40; radius: 20; opacity: Media.canToggle ? 1 : 0.45; color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, playHover.hovered ? 0.35 : 0.22)
                            border.color: Tokens.accent; border.width: 1
                            Text { anchors.centerIn: parent; text: Media.isPlaying ? "󰏤" : "󰐊"; font.pixelSize: 17; color: Tokens.accent }
                            HoverHandler { id: playHover; enabled: islandWindow.hasMedia && Media.canToggle; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: islandWindow.hasMedia && Media.canToggle; onTapped: Media.togglePlaying() }
                        }

                        Rectangle {
                            width: 32; height: 32; radius: 16; color: nextHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : "transparent"
                            Text { anchors.centerIn: parent; text: "󰒭"; font.pixelSize: 16; color: nextHover.hovered ? Tokens.accent : Tokens.text_secondary; opacity: Media.canNext ? 1 : 0.45 }
                            HoverHandler { id: nextHover; enabled: islandWindow.hasMedia && Media.canNext; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: islandWindow.hasMedia && Media.canNext; onTapped: Media.next() }
                        }
                    }
                }
            }
        }
    }

        Dashboard {
            id: dashboard
            anchors.fill: parent
            surface: islandContainer
            shape: islandShape
            cardDimensions: islandWindow.dashboardDimensions
            revealProgress: {
                const base = expanded ? islandWindow.dashboardOriginDims : islandWindow.currentDims;
                const target = islandWindow.dashboardDimensions;
                return Math.max(0, Math.min(1,
                    (islandShape.pillHeight - base.height) / Math.max(1, target.height - base.height),
                    (islandShape.pillWidth - base.width) / Math.max(1, target.width - base.width)));
            }
            onExpandedChanged: {
                if (expanded) {
                    islandWindow.collapse();
                    dismissTimer.stop();
                    islandWindow.activeAlert = null;
                }
                islandWindow.updateMode();
                if (!expanded) Qt.callLater(islandWindow.finishDashboardClose);
            }
        }
    }
}
