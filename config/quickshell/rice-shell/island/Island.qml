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
                height: IslandState.targetDimensions(IslandState.State.EXPANDED).height - 24

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

                readonly property bool seekAvailable: Media.activePlayer !== null
                    && Media.activePlayer.canSeek && Media.length > 0
                readonly property bool shuffleAvailable: Media.activePlayer !== null
                    && Media.activePlayer.canControl && Media.activePlayer.shuffleSupported
                readonly property bool loopAvailable: Media.activePlayer !== null
                    && Media.activePlayer.canControl && Media.activePlayer.loopSupported

                function toggleShuffle(): void {
                    if (shuffleAvailable && Media.activePlayer)
                        Media.activePlayer.shuffle = !Media.activePlayer.shuffle;
                }

                function cycleLoop(): void {
                    if (!loopAvailable) return;
                    Media.cycleLoop();
                }

                function seekByOffset(seconds: real): void {
                    if (seekAvailable) {
                        Media.setPosition(Math.max(0, Math.min(Media.length, Media.position + seconds)));
                    }
                }

                function seekAt(x: real): void {
                    if (seekAvailable && progressBarTrack.width > 0) {
                        const ratio = Math.max(0, Math.min(1, x / progressBarTrack.width));
                        Media.setPosition(ratio * Media.length);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 24

                    Rectangle {
                        Layout.preferredWidth: 68
                        Layout.minimumWidth: 68
                        Layout.maximumWidth: 68
                        Layout.preferredHeight: 68
                        Layout.alignment: Qt.AlignVCenter
                        radius: 14
                        color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                                       Tokens.surface_high.b, 0.72)
                        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                              Tokens.outline.b, 0.42)
                        border.width: 1
                        clip: true

                        Image {
                            id: expandedArtwork
                            anchors.fill: parent
                            source: Media.hasPlayer ? Media.trackArtUrl : ""
                            sourceSize.width: 204
                            sourceSize.height: 204
                            fillMode: Image.PreserveAspectCrop
                            visible: Media.hasPlayer && Media.trackArtUrl.length > 0
                                && status === Image.Ready
                            asynchronous: true
                        }

                        Text {
                            objectName: "expandedArtworkFallback"
                            anchors.centerIn: parent
                            text: "󰎆"
                            font.pixelSize: 26
                            color: Tokens.text_secondary
                            visible: expandedArtwork.status !== Image.Ready
                        }
                    }

                    ColumnLayout {
                        id: expandedMediaDetails
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 8
                        spacing: 3

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            text: islandWindow.hasMedia ? Media.trackTitle : "No media playing"
                            textFormat: Text.PlainText
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 15
                            text: islandWindow.hasMedia
                                ? (Media.trackArtist || "Active audio stream")
                                : "Play something to get started"
                            textFormat: Text.PlainText
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Tokens.text_secondary
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 17
                            spacing: 7
                            visible: Media.length > 0

                            Text {
                                text: Media.formatTime(Media.position)
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                                color: Tokens.text_secondary
                            }

                            Rectangle {
                                id: progressBarTrack
                                objectName: "mediaSeekTimeline"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 3
                                Layout.minimumHeight: 3
                                Layout.maximumHeight: 3
                                radius: 1.5
                                opacity: expandedMediaContent.seekAvailable ? 1 : 0.55
                                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                                               Tokens.surface_high.b, 0.88)
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.min(parent.width, Math.max(0, parent.width * Media.progress))
                                    radius: 1.5
                                    color: Tokens.accent

                                    Behavior on width {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.topMargin: -7
                                    anchors.bottomMargin: -7
                                    enabled: islandWindow.hasMedia && expandedMediaContent.seekAvailable
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onPressed: (mouse) => expandedMediaContent.seekAt(mouse.x)
                                    onPositionChanged: (mouse) => {
                                        if (pressed) expandedMediaContent.seekAt(mouse.x);
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

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            Layout.topMargin: 1
                            spacing: 7

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                objectName: "mediaShuffleButton"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 10
                                enabled: expandedMediaContent.shuffleAvailable
                                opacity: expandedMediaContent.shuffleAvailable ? 1 : 0.35
                                color: shuffleTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (shuffleHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                    Tokens.outline.b, 0.55)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒟"
                                    font.pixelSize: 13
                                    color: Media.activePlayer && Media.activePlayer.shuffle
                                        ? Tokens.accent : Tokens.text_secondary
                                }
                                HoverHandler {
                                    id: shuffleHover
                                    enabled: expandedMediaContent.shuffleAvailable
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: shuffleTap
                                    enabled: expandedMediaContent.shuffleAvailable
                                    onTapped: expandedMediaContent.toggleShuffle()
                                }
                            }

                            Rectangle {
                                objectName: "mediaPreviousButton"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                enabled: islandWindow.hasMedia
                                    && (Media.canPrev || expandedMediaContent.seekAvailable)
                                opacity: enabled ? 1 : 0.35
                                color: previousTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (previousHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b,
                                    previousHover.hovered || previousTap.pressed ? 0.7 : 0.36)

                                Text {
                                    objectName: "mediaPreviousActionLabel"
                                    anchors.centerIn: parent
                                    text: Media.canPrev ? "󰒮"
                                        : (expandedMediaContent.seekAvailable ? "−10s" : "󰒮")
                                    font.pixelSize: Media.canPrev || !expandedMediaContent.seekAvailable ? 14 : 8
                                    font.weight: Font.DemiBold
                                    color: previousHover.hovered ? Tokens.accent : Tokens.text_secondary
                                }
                                HoverHandler {
                                    id: previousHover
                                    enabled: islandWindow.hasMedia
                                        && (Media.canPrev || expandedMediaContent.seekAvailable)
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: previousTap
                                    enabled: islandWindow.hasMedia
                                        && (Media.canPrev || expandedMediaContent.seekAvailable)
                                    onTapped: {
                                        if (Media.canPrev) Media.previous();
                                        else expandedMediaContent.seekByOffset(-10);
                                    }
                                }
                            }

                            Rectangle {
                                objectName: "mediaPlayButton"
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 14
                                enabled: islandWindow.hasMedia && Media.canToggle
                                opacity: enabled ? 1 : 0.35
                                color: playTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.82)
                                    : (playHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.62)
                                        : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.36))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b,
                                    playHover.hovered || playTap.pressed ? 0.72 : 0.45)

                                Text {
                                    anchors.centerIn: parent
                                    text: Media.isPlaying ? "󰏤" : "󰐊"
                                    font.pixelSize: 14
                                    color: playHover.hovered ? Tokens.accent : Tokens.text_primary
                                }
                                HoverHandler {
                                    id: playHover
                                    enabled: islandWindow.hasMedia && Media.canToggle
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: playTap
                                    enabled: islandWindow.hasMedia && Media.canToggle
                                    onTapped: Media.togglePlaying()
                                }
                            }

                            Rectangle {
                                objectName: "mediaNextButton"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                enabled: islandWindow.hasMedia
                                    && (Media.canNext || expandedMediaContent.seekAvailable)
                                opacity: enabled ? 1 : 0.35
                                color: nextTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (nextHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b,
                                    nextHover.hovered || nextTap.pressed ? 0.7 : 0.36)

                                Text {
                                    objectName: "mediaNextActionLabel"
                                    anchors.centerIn: parent
                                    text: Media.canNext ? "󰒭"
                                        : (expandedMediaContent.seekAvailable ? "+10s" : "󰒭")
                                    font.pixelSize: Media.canNext || !expandedMediaContent.seekAvailable ? 14 : 8
                                    font.weight: Font.DemiBold
                                    color: nextHover.hovered ? Tokens.accent : Tokens.text_secondary
                                }
                                HoverHandler {
                                    id: nextHover
                                    enabled: islandWindow.hasMedia
                                        && (Media.canNext || expandedMediaContent.seekAvailable)
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: nextTap
                                    enabled: islandWindow.hasMedia
                                        && (Media.canNext || expandedMediaContent.seekAvailable)
                                    onTapped: {
                                        if (Media.canNext) Media.next();
                                        else expandedMediaContent.seekByOffset(10);
                                    }
                                }
                            }

                            Rectangle {
                                objectName: "mediaLoopButton"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 10
                                enabled: expandedMediaContent.loopAvailable
                                opacity: expandedMediaContent.loopAvailable ? 1 : 0.35
                                color: loopTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (loopHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                    Tokens.outline.b, 0.55)

                                Text {
                                    anchors.centerIn: parent
                                    text: Media.activePlayer
                                        && Media.activePlayer.loopState === Media.loopTrack
                                        ? "󰑗" : "󰑖"
                                    font.pixelSize: 13
                                    color: Media.activePlayer
                                        && Media.activePlayer.loopState !== Media.loopNone
                                        ? Tokens.accent : Tokens.text_secondary
                                }
                                HoverHandler {
                                    id: loopHover
                                    enabled: expandedMediaContent.loopAvailable
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: loopTap
                                    enabled: expandedMediaContent.loopAvailable
                                    onTapped: expandedMediaContent.cycleLoop()
                                }
                            }

                            Rectangle {
                                objectName: "mediaPinButton"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 10
                                color: pinTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (pinHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                    Tokens.outline.b, pinHover.hovered ? 0.7 : 0.36)

                                Text {
                                    anchors.centerIn: parent
                                    text: islandWindow.isPinned ? "󰅖" : "󰐃"
                                    font.pixelSize: 13
                                    color: pinHover.hovered || islandWindow.isPinned ? Tokens.accent : Tokens.text_secondary
                                }
                                HoverHandler {
                                    id: pinHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    id: pinTap
                                    onTapped: {
                                        if (islandWindow.isPinned) islandWindow.collapse();
                                        else islandWindow.isPinned = true;
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
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
