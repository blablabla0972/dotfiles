pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
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
    visible: targetScreen !== null
    readonly property real topGap: 6
    readonly property real idleHeight: IslandState.targetDimensions(IslandState.State.IDLE).height
    readonly property real trackingHeight: IslandState.targetDimensions(IslandState.State.EXPANDED).height
    readonly property real extraTopGap: Math.max(0, Math.min(12,
        (targetScreen?.height ?? 0) - Math.max(trackingHeight, dashboardDimensions.height) - topGap - 8))
    readonly property real targetTopGap: topGapForHeight(currentDims.height)

    function topGapForHeight(height: real): real {
        const heightProgress = Math.max(0, Math.min(1,
            (height - idleHeight) / Math.max(1, trackingHeight - idleHeight)));
        return topGap + extraTopGap * heightProgress;
    }
    // Grow ahead of the pill animation; delay shrinking until the morph settles.
    readonly property real requestedLayerHeight: Math.ceil(Math.max(currentDims.height, islandShape.pillHeight)
        + Math.max(targetTopGap, islandContainer.y) + 8)
    property real retainedLayerHeight: idleHeight + topGap + 8
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

    // Follow the surface and keep the hover path back to its resting position.
    mask: Region {
        item: islandWindow.modalOpen ? scrim : null
        x: islandContainer.x + islandShape.a
        y: Math.min(islandWindow.topGap, islandContainer.y)
        width: islandShape.pillWidth
        height: islandShape.pillHeight + Math.max(0, islandContainer.y - islandWindow.topGap)
        topLeftRadius: islandWindow.modalOpen ? 0 : islandShape.r
        topRightRadius: islandWindow.modalOpen ? 0 : islandShape.r
        bottomLeftRadius: islandWindow.modalOpen ? 0 : islandShape.r
        bottomRightRadius: islandWindow.modalOpen ? 0 : islandShape.r
    }

    signal requestDashboard(string tab)
    signal requestSettings()

    // State properties
    property string activeMode: "idle"
    property bool contracting: false
    property var activeAlert: null
    property bool hoverPreview: false
    property bool isPinned: false
    readonly property bool dashboardShowing: dashboard.expanded || dashboard.closing
    readonly property bool dashboardExpanded: dashboard.expanded
    readonly property string dashboardCurrentTab: dashboard.currentTab
    // Release fullscreen input when Dashboard starts closing; keep its geometry until the morph ends.
    readonly property bool modalOpen: isPinned || dashboard.expanded
    function toggleDashboard(tab: string): void {
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

    readonly property bool dashboardCloseReady: dashboard.closing && !dashboard.expanded
        && activeMode !== IslandState.State.DASHBOARD && !islandShape.morphing
        && dashboardMotion.opacity === 0
        && islandShape.pillWidth === currentDims.width && islandShape.pillHeight === currentDims.height
    onDashboardCloseReadyChanged: {
        if (dashboardCloseReady) Qt.callLater(() => {
            if (islandWindow.dashboardCloseReady) dashboard.closing = false;
        });
    }

    // Media bindings from native Mpris service
    property bool showMediaPreview: true
    readonly property bool hasMedia: showMediaPreview && Media.hasPlayer
    readonly property string mediaTitle: Media.trackTitle

    // OSD parameters
    property real osdProgress: IslandState.normalizeOsdProgress(Audio.volume, "volume")
    property string osdKind: "volume"
    readonly property real osdFill: IslandState.osdFill(osdProgress)
    property string osdIcon: Audio.muted ? "󰝟" : "󰕾"

    // Synchronize dimensions based on active mode
    readonly property var dashboardDimensions: IslandState.dashboardGeometry(
        targetScreen?.width, targetScreen?.height, 7)
    property var currentDims: IslandState.targetDimensions(IslandState.State.IDLE)
    readonly property color islandColor: Tokens.mode === "dark" ? Qt.darker(Tokens.surface, 1.65) : Tokens.surface

    function collapse(): void {
        hoverDwell.stop();
        hoverGrace.stop();
        hoverPreview = false;
        isPinned = false;
        updateMode();
    }
    property var renderedNotification: null
    function syncNotification(): void {
        // Keep the outgoing layout and actions intact until the fade completes.
        if (notificationMotion.presence === 0)
            renderedNotification = activeAlert?.type === IslandState.State.NOTIFICATION ? activeAlert : null;
    }
    readonly property string notificationIconSource: {
        var icon = renderedNotification?.appIcon || "";
        if (!icon) return "";
        if (icon.charAt(0) === "/" || icon.indexOf(":/") >= 0 || icon.indexOf("://") >= 0) return icon;
        return Quickshell.iconPath(icon, true);
    }

    function updateMode(): void {
        const nextMode = IslandState.resolveState(activeAlert, hasMedia, hoverPreview, isPinned, dashboard.expanded);
        const nextDims = nextMode === IslandState.State.DASHBOARD
            ? dashboardDimensions
            : IslandState.targetDimensions(nextMode,
                nextMode === IslandState.State.NOTIFICATION ? activeAlert : null);
        const modeChanged = nextMode !== activeMode;
        const sizeChanged = nextDims.width !== currentDims.width || nextDims.height !== currentDims.height
            || nextDims.radius !== currentDims.radius;
        if (!modeChanged && !sizeChanged) return;
        // Latch damping before retargeting, including interrupted spring motion.
        const fromHeight = islandShape ? islandShape.pillHeight : currentDims.height;
        const fromWidth = islandShape ? islandShape.pillWidth : currentDims.width;
        contracting = nextDims.height < fromHeight
            || (nextDims.height === fromHeight && nextDims.width < fromWidth);
        if (sizeChanged) currentDims = nextDims;
        if (modeChanged) activeMode = nextMode;
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
        syncNotification();
        updateMode();
        if (!activeAlert && hoverHandler.hovered && hasMedia && !hoverPreview
            && !modalOpen && !dashboardShowing)
            hoverDwell.restart();
    }
    onDashboardDimensionsChanged: updateMode()

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
        osdKind = kind === "brightness" || kind === "microphone" ? kind : "volume";
        osdProgress = IslandState.normalizeOsdProgress(progress, osdKind);
        if (activeAlert?.type !== IslandState.State.OSD)
            activeAlert = { type: IslandState.State.OSD };
        dismissTimer.interval = osdKind === "microphone" ? 1400 : 2200;
        dismissTimer.restart();
    }

    function triggerNotification(summary: string, body: string, appName: string, appIcon: string,
                                 notificationId: int, actions): void {
        if (modalOpen || dashboardShowing) return;
        activeAlert = {
            type: IslandState.State.NOTIFICATION,
            notificationId: notificationId,
            summary: summary,
            body: body,
            appName: appName || "",
            appIcon: appIcon || "",
            actions: Array.isArray(actions)
                ? actions.filter(action => typeof action?.id === "string" && typeof action?.text === "string")
                : []
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
            anchors.topMargin: islandWindow.topGapForHeight(islandShape.pillHeight)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -dashboard.drawerOffset
            width: islandShape.width
            height: islandShape.height

            IslandShape {
                id: islandShape
                anchors.centerIn: parent
                targetGeometry: Qt.vector3d(islandWindow.currentDims.width,
                    islandWindow.currentDims.height, islandWindow.currentDims.radius)
                antiCornerRadius: 0
                contracting: islandWindow.contracting
                fillColor: islandWindow.islandColor
                borderColor: Tokens.outline
                showAntiCorners: false
            }

            HoverHandler {
                id: hoverHandler
                margin: Math.max(0, islandContainer.y - islandWindow.topGap)
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
                onTapped: islandWindow.requestDashboard("")
            }

            TapHandler {
                enabled: !islandWindow.dashboardShowing
                acceptedButtons: Qt.RightButton
                onTapped: {
                    islandWindow.collapse();
                    islandWindow.requestDashboard("");
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
                    id: idleContent
                    IslandContentMotion {
                        id: idleMotion
                        shape: islandShape
                        active: islandWindow.activeMode === IslandState.State.IDLE
                        contentWidth: idleContent.width
                        contentHeight: idleContent.height
                    }
                    opacity: idleMotion.opacity
                    scale: idleMotion.scale
                    visible: opacity > 0
                    enabled: idleMotion.active && opacity > 0.9
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
                    id: compactMediaContent
                    objectName: "compactMediaContent"
                    IslandContentMotion {
                        id: compactMotion
                        shape: islandShape
                        active: islandWindow.activeMode === IslandState.State.MEDIA
                        contentWidth: compactMediaContent.width
                        contentHeight: compactMediaContent.height
                    }
                    opacity: compactMotion.opacity
                    scale: compactMotion.scale
                    visible: opacity > 0
                    enabled: compactMotion.active && opacity > 0.9
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

            // Compact feedback inspired by Tide Island: a clear readout and progress ring.
            RowLayout {
                id: osdContent
                IslandContentMotion {
                    id: osdMotion
                    shape: islandShape
                    active: islandWindow.activeMode === IslandState.State.OSD
                    contentWidth: osdContent.width
                    contentHeight: osdContent.height
                }
                opacity: osdMotion.opacity
                scale: osdMotion.scale
                visible: opacity > 0
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.OSD).width - 32
                height: 34
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.14)
                    Text {
                        anchors.centerIn: parent
                        text: islandWindow.osdIcon
                        font.pixelSize: 17
                        color: Tokens.accent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: islandWindow.osdKind === "brightness" ? qsTr("Brightness")
                            : islandWindow.osdKind === "microphone" ? qsTr("Microphone")
                            : islandWindow.osdProgress > 1 ? qsTr("Volume · Boost") : qsTr("Volume")
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                    }
                    Text {
                        objectName: "feedbackOsdReadout"
                        text: islandWindow.osdKind === "microphone"
                            ? (islandWindow.osdProgress === 0 ? qsTr("Muted") : qsTr("On"))
                            : Math.round(islandWindow.osdProgress * 100) + "%"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Tokens.text_primary
                    }
                }

                Shape {
                    id: osdRing
                    objectName: "feedbackOsdRing"
                    visible: islandWindow.osdKind !== "microphone"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real progress: islandWindow.osdFill
                    property real displayedProgress: progress
                    Behavior on displayedProgress {
                        enabled: osdContent.opacity > 0.95
                        SmoothedAnimation { velocity: 1.8; duration: 180 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.rgba(Tokens.text_primary.r, Tokens.text_primary.g, Tokens.text_primary.b, 0.16)
                        strokeWidth: 3
                        PathAngleArc {
                            centerX: 15; centerY: 15
                            radiusX: 12; radiusY: 12
                            startAngle: -90; sweepAngle: 360
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Tokens.text_primary
                        strokeWidth: 3
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 15; centerY: 15
                            radiusX: 12; radiusY: 12
                            startAngle: -90
                            sweepAngle: 360 * osdRing.displayedProgress
                        }
                    }
                }
            }

            // 4. Notification Alert Content
            RowLayout {
                id: notificationContent
                IslandContentMotion {
                    id: notificationMotion
                    shape: islandShape
                    active: islandWindow.activeMode === IslandState.State.NOTIFICATION
                        && islandWindow.renderedNotification !== null
                        && islandWindow.renderedNotification === islandWindow.activeAlert
                    contentWidth: notificationContent.width
                    contentHeight: notificationContent.height
                    onPresenceChanged: islandWindow.syncNotification()
                }
                opacity: notificationMotion.opacity
                scale: notificationMotion.scale
                visible: opacity > 0
                enabled: notificationMotion.active && opacity > 0.9
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.NOTIFICATION).width - 32
                height: IslandState.targetDimensions(IslandState.State.NOTIFICATION,
                    islandWindow.renderedNotification).height - 24
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
                        text: islandWindow.renderedNotification?.appName || "Notification"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Tokens.accent
                        elide: Text.ElideRight
                    }

                    Text {
                        objectName: "notificationIslandSummary"
                        Layout.fillWidth: true
                        text: islandWindow.renderedNotification?.summary || "Notification"
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
                        text: islandWindow.renderedNotification?.body || ""
                        font.pixelSize: 12
                        color: Tokens.text_secondary
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: (islandWindow.renderedNotification?.actions?.length ?? 0) > 0
                        spacing: 6

                        Repeater {
                            model: islandWindow.renderedNotification?.actions ?? []
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 8
                                color: actionHover.hovered ? Tokens.surface_high : Tokens.surface
                                border.width: 1
                                border.color: Tokens.outline

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    font.pixelSize: 10
                                    color: Tokens.text_primary
                                    elide: Text.ElideRight
                                }

                                HoverHandler {
                                    id: actionHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: {
                                        DesktopControls.requestNotificationAction(
                                            islandWindow.renderedNotification.notificationId, modelData.id);
                                        islandWindow.activeAlert = null;
                                        dismissTimer.stop();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 5. Expanded Media Capsule Content
            Item {
                id: expandedMediaContent
                IslandContentMotion {
                    id: expandedMotion
                    shape: islandShape
                    active: islandWindow.activeMode === IslandState.State.EXPANDED
                    contentWidth: expandedMediaContent.width
                    contentHeight: expandedMediaContent.height
                }
                opacity: expandedMotion.opacity
                scale: expandedMotion.scale
                visible: opacity > 0
                // Enable visible controls during the final part of the reveal animation.
                enabled: expandedMotion.active && opacity > 0.5
                anchors.centerIn: parent
                width: IslandState.targetDimensions(IslandState.State.EXPANDED).width - 40
                height: IslandState.targetDimensions(IslandState.State.EXPANDED).height - 32

                // MPRIS position is read on demand; refresh bindings while the card is visible.
                Timer {
                    interval: 1000
                    repeat: true
                    running: expandedMotion.active && expandedMediaContent.visible && Media.isPlaying
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
                    spacing: 20

                    Rectangle {
                        Layout.preferredWidth: 100
                        Layout.minimumWidth: 100
                        Layout.maximumWidth: 100
                        Layout.preferredHeight: 100
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                                       Tokens.surface_high.b, 0.72)
                        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                              Tokens.outline.b, 0.42)
                        border.width: 1

                        Image {
                            id: expandedArtwork
                            anchors.fill: parent
                            source: Media.hasPlayer ? Media.trackArtUrl : ""
                            sourceSize.width: 300
                            sourceSize.height: 300
                            fillMode: Image.PreserveAspectCrop
                            visible: Media.hasPlayer && Media.trackArtUrl.length > 0
                                && status === Image.Ready
                            asynchronous: true
                            layer.enabled: expandedMediaContent.visible && visible
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: expandedArtworkMask
                            }
                        }

                        Rectangle {
                            id: expandedArtworkMask
                            anchors.fill: expandedArtwork
                            radius: 18
                            color: "white"
                            layer.enabled: expandedArtwork.layer.enabled
                            visible: false
                        }

                        Text {
                            objectName: "expandedArtworkFallback"
                            anchors.centerIn: parent
                            text: "󰎆"
                            font.pixelSize: 32
                            color: Tokens.text_secondary
                            visible: expandedArtwork.status !== Image.Ready
                        }
                    }

                    ColumnLayout {
                        id: expandedMediaDetails
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            text: islandWindow.hasMedia ? Media.trackTitle : "No media playing"
                            textFormat: Text.PlainText
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
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
                            Layout.preferredHeight: 20
                            spacing: 7
                            visible: Media.length > 0

                            Text {
                                text: Media.formatTime(Media.position)
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                                color: Tokens.text_secondary
                            }

                            Rectangle {
                                id: progressBarTrack
                                objectName: "mediaSeekTimeline"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                Layout.minimumHeight: 4
                                Layout.maximumHeight: 4
                                radius: 2
                                opacity: expandedMediaContent.seekAvailable ? 1 : 0.55
                                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                                               Tokens.surface_high.b, 0.88)

                                Rectangle {
                                    height: parent.height
                                    width: Math.min(parent.width, Math.max(0, parent.width * Media.progress))
                                    radius: 2
                                    color: Tokens.accent

                                    Behavior on width {
                                        enabled: expandedMediaContent.visible
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
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                                color: Tokens.text_secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            Layout.topMargin: 2
                            spacing: 7

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                objectName: "mediaShuffleButton"
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 15
                                enabled: expandedMediaContent.shuffleAvailable
                                opacity: expandedMediaContent.shuffleAvailable ? 1 : 0.35
                                color: shuffleTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (shuffleHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒟"
                                    font.pixelSize: 15
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
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 17
                                enabled: islandWindow.hasMedia
                                    && (Media.canPrev || expandedMediaContent.seekAvailable)
                                opacity: enabled ? 1 : 0.35
                                color: previousTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (previousHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : "transparent")
                                Text {
                                    objectName: "mediaPreviousActionLabel"
                                    anchors.centerIn: parent
                                    text: Media.canPrev ? "󰒮"
                                        : (expandedMediaContent.seekAvailable ? "−10s" : "󰒮")
                                    font.pixelSize: Media.canPrev || !expandedMediaContent.seekAvailable ? 19 : 10
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
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                radius: 21
                                enabled: islandWindow.hasMedia && Media.canToggle
                                opacity: enabled ? 1 : 0.35
                                color: playTap.pressed ? Qt.darker(Tokens.accent, 1.12)
                                    : (playHover.hovered ? Qt.lighter(Tokens.accent, 1.08) : Tokens.accent)

                                Text {
                                    anchors.centerIn: parent
                                    text: Media.isPlaying ? "󰏤" : "󰐊"
                                    font.pixelSize: 23
                                    color: Tokens.on_accent
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
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 17
                                enabled: islandWindow.hasMedia
                                    && (Media.canNext || expandedMediaContent.seekAvailable)
                                opacity: enabled ? 1 : 0.35
                                color: nextTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (nextHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : "transparent")
                                Text {
                                    objectName: "mediaNextActionLabel"
                                    anchors.centerIn: parent
                                    text: Media.canNext ? "󰒭"
                                        : (expandedMediaContent.seekAvailable ? "+10s" : "󰒭")
                                    font.pixelSize: Media.canNext || !expandedMediaContent.seekAvailable ? 19 : 10
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
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 15
                                enabled: expandedMediaContent.loopAvailable
                                opacity: expandedMediaContent.loopAvailable ? 1 : 0.35
                                color: loopTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (loopHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: Media.activePlayer
                                        && Media.activePlayer.loopState === Media.loopTrack
                                        ? "󰑗" : "󰑖"
                                    font.pixelSize: 15
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
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 15
                                color: pinTap.pressed
                                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
                                    : (pinHover.hovered
                                        ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.46)
                                        : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: islandWindow.isPinned ? "󰅖" : "󰐃"
                                    font.pixelSize: 15
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
            IslandContentMotion {
                id: dashboardMotion
                shape: islandShape
                active: dashboard.expanded
                contentWidth: islandWindow.dashboardDimensions.width
                contentHeight: islandWindow.dashboardDimensions.height
                revealStart: 0.22
            }
            revealProgress: dashboardMotion.opacity
            onRequestSettings: islandWindow.requestSettings()
            onExpandedChanged: {
                if (expanded) {
                    islandWindow.collapse();
                    dismissTimer.stop();
                    islandWindow.activeAlert = null;
                }
                islandWindow.updateMode();
            }
        }
    }
}
