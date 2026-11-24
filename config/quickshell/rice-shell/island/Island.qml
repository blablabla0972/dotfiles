pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Templates as T
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
        return topGap + extraTopGap * heightProgress * heightProgress * (3 - 2 * heightProgress);
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
    Component.onCompleted: {
        updateMode();
        reconcileLayerHeight();
    }

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
        x: islandWindow.modalOpen ? 0 : islandContainer.x + islandShape.a
        y: islandWindow.modalOpen ? 0 : Math.min(islandWindow.topGap, islandContainer.y)
        width: islandWindow.modalOpen ? 0 : islandShape.pillWidth
        height: islandWindow.modalOpen ? 0 : islandShape.pillHeight + Math.max(0, islandContainer.y - islandWindow.topGap)
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
    readonly property real capsuleWidthLimit: Math.max(1, (targetScreen?.width || 1920) - 16)

    // OSD parameters
    property real osdProgress: IslandState.normalizeOsdProgress(Audio.volume, "volume")
    property string osdKind: "volume"
    readonly property real osdFill: IslandState.osdFill(osdProgress)
    property string osdIcon: Audio.muted ? "󰝟" : "󰕾"

    // Synchronize dimensions based on active mode
    readonly property var dashboardDimensions: IslandState.dashboardGeometry(
        targetScreen?.width, targetScreen?.height, 7)
    property var currentDims: IslandState.targetDimensions(IslandState.State.IDLE)
    readonly property color islandColor: Tokens.mode === "dark" ? Qt.darker(Tokens.surface, 1.38) : Tokens.surface

    function capsuleWidth(mode: string): real {
        return Math.min(capsuleWidthLimit, IslandState.targetDimensions(mode).width);
    }

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
        if (!dashboard || !islandShape) return;
        const nextMode = IslandState.resolveState(activeAlert, hasMedia, hoverPreview, isPinned, dashboard.expanded);
        const nextDims = nextMode === IslandState.State.DASHBOARD
            ? dashboardDimensions
            : IslandState.targetDimensions(nextMode,
                nextMode === IslandState.State.NOTIFICATION ? activeAlert : null);
        if (nextMode !== IslandState.State.DASHBOARD)
            nextDims.width = Math.min(nextDims.width, capsuleWidthLimit);
        const modeChanged = nextMode !== activeMode;
        const sizeChanged = nextDims.width !== currentDims.width || nextDims.height !== currentDims.height
            || nextDims.radius !== currentDims.radius;
        if (!modeChanged && !sizeChanged) return;
        // Latch damping before retargeting, including interrupted spring motion.
        if (sizeChanged)
            islandShape.mediaBounce = (activeMode === IslandState.State.MEDIA && nextMode === IslandState.State.EXPANDED)
                || (activeMode === IslandState.State.EXPANDED && nextMode === IslandState.State.MEDIA);
        const fromHeight = islandShape.pillHeight;
        const fromWidth = islandShape.pillWidth;
        contracting = nextDims.height < fromHeight
            || (nextDims.height === fromHeight && nextDims.width < fromWidth);
        if (sizeChanged) currentDims = nextDims;
        if (modeChanged) activeMode = nextMode;
    }

    onHoverPreviewChanged: updateMode()
    onHasMediaChanged: {
        if (hasMedia) updateMode();
        else collapse();
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
    onCapsuleWidthLimitChanged: updateMode()

    Timer {
        id: hoverDwell
        interval: 100
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
        if (notificationHover.hovered) dismissTimer.stop();
        else dismissTimer.restart();
    }

    Timer {
        id: dismissTimer
        interval: 2200
        repeat: false
        onTriggered: islandWindow.activeAlert = null
    }

    Shortcut {
        sequence: "Escape"
        enabled: islandWindow.isPinned && !dashboard.expanded
        context: Qt.WindowShortcut
        onActivated: islandWindow.collapse()
    }

    // Input surface for outside clicks while the island is modal.
    Item {
        id: scrim
        anchors.fill: parent

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
            anchors.alignWhenCentered: false
            anchors.horizontalCenterOffset: -dashboard.drawerOffset
            width: islandShape.width
            height: islandShape.height

            IslandShape {
                id: islandShape
                anchors.centerIn: parent
                targetGeometry: Qt.vector3d(islandWindow.currentDims.width,
                    islandWindow.currentDims.height, islandWindow.currentDims.radius)
                contracting: islandWindow.contracting
                unfoldStart: islandWindow.trackingHeight
                unfoldEnd: islandWindow.dashboardDimensions.height
                fillColor: islandWindow.islandColor
                borderColor: Qt.tint(islandWindow.islandColor, Qt.rgba(Tokens.text_primary.r,
                    Tokens.text_primary.g, Tokens.text_primary.b, hoverHandler.hovered ? 0.28 : 0.17))
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

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !islandWindow.dashboardShowing && (islandWindow.activeMode === IslandState.State.IDLE
                    || islandWindow.activeMode === IslandState.State.NOTIFICATION
                    || islandWindow.activeMode === IslandState.State.OSD)
                onClicked: islandWindow.requestDashboard("")
                Accessible.role: Accessible.Button
                Accessible.ignored: !enabled
                Accessible.name: qsTr("Open Control Center")
                Accessible.onPressAction: islandWindow.requestDashboard("")
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
                        contentWidth: islandWindow.capsuleWidth(IslandState.State.IDLE)
                        contentHeight: islandWindow.idleHeight
                    }
                    opacity: idleMotion.opacity
                    scale: idleMotion.scale
                    anchors.verticalCenterOffset: idleMotion.offsetY
                    visible: opacity > 0
                    enabled: idleMotion.active && opacity > 0.9
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: 11
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: "󰍹"
                            font.pixelSize: 12
                            color: Tokens.accent
                        }
                    }
                    Text {
                        text: qsTr("Control Center")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Tokens.text_primary
                    }
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
                    anchors.verticalCenterOffset: compactMotion.offsetY
                    visible: opacity > 0
                    enabled: compactMotion.active && opacity > 0.9
                    anchors.centerIn: parent
                    width: Math.max(1, islandWindow.capsuleWidth(IslandState.State.MEDIA) - 16)
                    height: 28
                    spacing: 8

                    T.AbstractButton {
                        id: compactTrack
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: islandWindow.hasMedia ? Media.trackTitle : ""
                        Accessible.name: qsTr("Open player: %1").arg(text)
                        onClicked: islandWindow.isPinned = true
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        contentItem: RowLayout {
                            spacing: 8
                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: 7
                                color: Tokens.surface_high
                                Image {
                                    id: miniArtwork
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    source: compactMediaContent.visible ? Media.trackArtUrl : ""
                                    sourceSize: Qt.size(48, 48)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                                Text {
                                    visible: miniArtwork.status !== Image.Ready
                                    anchors.centerIn: parent
                                    text: "󰎆"
                                    font.pixelSize: 13
                                    color: Tokens.accent
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: compactTrack.text
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }
                        }
                    }
                    IslandButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 26
                        enabled: islandWindow.hasMedia && Media.canToggle
                        highlighted: true
                        text: Media.isPlaying ? qsTr("Pause") : qsTr("Play")
                        glyph: Media.isPlaying ? "󰏤" : "󰐊"
                        onClicked: Media.togglePlaying()
                    }
                }

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
                    anchors.verticalCenterOffset: osdMotion.offsetY
                    visible: opacity > 0
                    anchors.centerIn: parent
                    width: Math.max(1, islandWindow.capsuleWidth(IslandState.State.OSD) - 28)
                    height: 34
                    spacing: 10
                    readonly property bool microphone: islandWindow.osdKind === "microphone"
                    readonly property color ink: microphone && islandWindow.osdProgress === 0
                        ? Tokens.danger : Tokens.accent

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: Qt.rgba(osdContent.ink.r, osdContent.ink.g, osdContent.ink.b, 0.12)
                        Shape {
                            id: osdRing
                            objectName: "feedbackOsdRing"
                            anchors.fill: parent
                            visible: !osdContent.microphone
                            preferredRendererType: Shape.CurveRenderer
                            property real displayedProgress: islandWindow.osdFill
                            Behavior on displayedProgress {
                                enabled: osdContent.visible && !osdContent.microphone
                                SmoothedAnimation { velocity: 2; duration: 160 }
                            }
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: osdContent.ink
                                strokeWidth: 2
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 16; centerY: 16
                                    radiusX: 14; radiusY: 14
                                    startAngle: -90
                                    sweepAngle: 360 * osdRing.displayedProgress
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: islandWindow.osdIcon
                            font.pixelSize: 15
                            color: osdContent.ink
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: islandWindow.osdKind === "brightness" ? qsTr("Brightness")
                            : osdContent.microphone ? qsTr("Microphone")
                            : islandWindow.osdProgress > 1 ? qsTr("Volume · Boost") : qsTr("Volume")
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: Tokens.text_secondary
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "feedbackOsdReadout"
                        text: osdContent.microphone ? (islandWindow.osdProgress === 0 ? qsTr("Muted") : qsTr("On"))
                            : Math.round(islandWindow.osdProgress * 100) + "%"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Tokens.text_primary
                    }
                }

                RowLayout {
                    id: notificationContent
                    HoverHandler {
                        id: notificationHover
                        enabled: notificationContent.enabled
                        onHoveredChanged: {
                            if (islandWindow.activeAlert?.type !== IslandState.State.NOTIFICATION) return;
                            if (hovered) dismissTimer.stop();
                            else dismissTimer.restart();
                        }
                    }
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
                    anchors.verticalCenterOffset: notificationMotion.offsetY
                    visible: opacity > 0
                    enabled: notificationMotion.active && opacity > 0.9
                    anchors.centerIn: parent
                    width: Math.max(1, islandWindow.capsuleWidth(IslandState.State.NOTIFICATION) - 32)
                    height: IslandState.targetDimensions(IslandState.State.NOTIFICATION,
                        islandWindow.renderedNotification).height - 16
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignTop
                        radius: 13
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.14)

                        Image {
                            id: notificationAppIcon
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            source: islandWindow.notificationIconSource
                            sourceSize: Qt.size(Math.ceil(width * Math.max(2, Screen.devicePixelRatio)),
                                                Math.ceil(height * Math.max(2, Screen.devicePixelRatio)))
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
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            visible: text.length > 0
                            text: islandWindow.renderedNotification?.appName || ""
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Tokens.accent
                            elide: Text.ElideRight
                        }

                        Text {
                            objectName: "notificationIslandSummary"
                            Layout.fillWidth: true
                            text: islandWindow.renderedNotification?.summary || qsTr("Notification")
                            textFormat: Text.PlainText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            Layout.maximumHeight: 34
                            textFormat: Text.PlainText
                            text: islandWindow.renderedNotification?.body || ""
                            font.pixelSize: 12
                            color: Tokens.text_secondary
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                        }

                        ListView {
                            id: actionList
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            Layout.topMargin: 2
                            visible: count > 0
                            model: islandWindow.renderedNotification?.actions ?? []
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: IslandButton {
                                required property var modelData
                                text: modelData.text
                                highlighted: true
                                height: 26
                                width: Math.min(implicitWidth, actionList.width)
                                horizontalPadding: 12
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                onClicked: {
                                    DesktopControls.requestNotificationAction(
                                        islandWindow.renderedNotification.notificationId, modelData.id);
                                    islandWindow.activeAlert = null;
                                    dismissTimer.stop();
                                }
                            }
                        }
                    }
                }

                Loader {
                    id: expandedMediaContent
                    // Prepare the player during hover dwell, not on the first morph frame.
                    active: islandWindow.activeMode === IslandState.State.EXPANDED || expandedMotion.presence > 0
                        || (hoverHandler.hovered && islandWindow.activeMode === IslandState.State.MEDIA)
                    asynchronous: islandWindow.activeMode !== IslandState.State.EXPANDED
                    focus: islandWindow.isPinned
                    IslandContentMotion {
                        id: expandedMotion
                        shape: islandShape
                        active: islandWindow.activeMode === IslandState.State.EXPANDED
                        contentWidth: expandedMediaContent.width
                        contentHeight: expandedMediaContent.height
                        enterDuration: 160
                    }
                    opacity: expandedMotion.opacity
                    scale: expandedMotion.scale
                    anchors.verticalCenterOffset: expandedMotion.offsetY
                    visible: opacity > 0
                    // Enable visible controls during the final part of the reveal animation.
                    enabled: expandedMotion.active && opacity > 0.5
                    anchors.centerIn: parent
                    width: Math.max(1, islandWindow.capsuleWidth(IslandState.State.EXPANDED) - 32)
                    height: IslandState.targetDimensions(IslandState.State.EXPANDED).height - 24

                    readonly property bool seekAvailable: Media.activePlayer !== null
                        && Media.activePlayer.canSeek && Media.length > 0
                    readonly property bool shuffleAvailable: Media.activePlayer !== null
                        && Media.activePlayer.canControl && Media.activePlayer.shuffleSupported
                    readonly property bool loopAvailable: Media.activePlayer !== null
                        && Media.activePlayer.canControl && Media.activePlayer.loopSupported

                    sourceComponent: ColumnLayout {
                        spacing: 4

                        // MPRIS reports position on demand between player events.
                        Timer {
                            interval: 1000
                            repeat: true
                            running: expandedMotion.active && Media.isPlaying && Media.length > 0
                                && Media.activePlayer?.positionSupported && !progressBarTrack.pressed
                            onTriggered: Media.activePlayer?.positionChanged()
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 54
                                radius: 12
                                color: Tokens.surface_high
                                Image {
                                    id: expandedArtwork
                                    anchors.fill: parent
                                    source: Media.trackArtUrl
                                    sourceSize.width: Math.ceil(54 * Screen.devicePixelRatio)
                                    sourceSize.height: Math.ceil(54 * Screen.devicePixelRatio)
                                    fillMode: Image.PreserveAspectCrop
                                    opacity: status === Image.Ready ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    asynchronous: true
                                    layer.enabled: visible
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: expandedArtworkMask
                                    }
                                }
                                Rectangle {
                                    id: expandedArtworkMask
                                    anchors.fill: parent
                                    radius: parent.radius
                                    layer.enabled: expandedArtwork.layer.enabled
                                    visible: false
                                }
                                Text {
                                    objectName: "expandedArtworkFallback"
                                    anchors.centerIn: parent
                                    visible: !expandedArtwork.visible
                                    text: "󰎆"
                                    font.pixelSize: 25
                                    color: Tokens.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: islandWindow.hasMedia ? Media.trackTitle : qsTr("No media playing")
                                    textFormat: Text.PlainText
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: Tokens.text_primary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: Media.trackArtist || Media.trackAlbum || Media.activePlayer?.identity || ""
                                    visible: text.length > 0
                                    textFormat: Text.PlainText
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: Tokens.text_secondary
                                }
                            }

                            IslandButton {
                                objectName: "mediaPinButton"
                                text: islandWindow.isPinned ? qsTr("Close player") : qsTr("Pin player")
                                glyph: islandWindow.isPinned ? "󰅖" : "󰐃"
                                highlighted: islandWindow.isPinned
                                onClicked: {
                                    if (islandWindow.isPinned) islandWindow.collapse();
                                    else islandWindow.isPinned = true;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: Media.length > 0
                            spacing: 6
                            Text {
                                text: Media.formatTime(progressBarTrack.pressed
                                    ? progressBarTrack.valueAt(progressBarTrack.position) : Media.position)
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                                color: Tokens.text_secondary
                            }
                            T.Slider {
                                id: progressBarTrack
                                objectName: "mediaSeekTimeline"
                                Layout.fillWidth: true
                                implicitHeight: 20
                                horizontalPadding: 4
                                enabled: expandedMediaContent.seekAvailable
                                hoverEnabled: true
                                live: false
                                to: Media.length || 1
                                value: Media.position
                                stepSize: 1
                                Accessible.name: qsTr("Playback position")
                                onPressedChanged: {
                                    if (!pressed && enabled && expandedMotion.active)
                                        Media.setPosition(valueAt(position));
                                }
                                onMoved: if (!pressed) Media.setPosition(value)
                                background: Rectangle {
                                    x: progressBarTrack.leftPadding
                                    y: (progressBarTrack.height - height) / 2
                                    width: progressBarTrack.availableWidth
                                    height: 4
                                    radius: 2
                                    color: Tokens.surface_high
                                    Rectangle {
                                        width: parent.width * progressBarTrack.position
                                        x: progressBarTrack.mirrored ? parent.width - width : 0
                                        height: parent.height
                                        radius: parent.radius
                                        color: Tokens.accent
                                    }
                                }
                                handle: Rectangle {
                                    width: 8; height: 8; radius: 4
                                    x: progressBarTrack.leftPadding + progressBarTrack.visualPosition
                                        * progressBarTrack.availableWidth - width / 2
                                    y: (progressBarTrack.height - height) / 2
                                    color: Tokens.accent
                                    opacity: progressBarTrack.enabled && (progressBarTrack.hovered
                                        || progressBarTrack.pressed || progressBarTrack.visualFocus) ? 1 : 0
                                    scale: 0.75 + 0.25 * opacity
                                    Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }
                                }
                            }
                            Text {
                                text: Media.formatTime(Media.length)
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                                color: Tokens.text_secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            IslandButton {
                                objectName: "mediaShuffleButton"
                                text: qsTr("Shuffle")
                                glyph: "󰒟"
                                enabled: expandedMediaContent.shuffleAvailable
                                highlighted: Media.activePlayer?.shuffle ?? false
                                Accessible.checkable: true
                                Accessible.checked: highlighted
                                onClicked: Media.activePlayer.shuffle = !Media.activePlayer.shuffle
                            }
                            Item { Layout.fillWidth: true }
                            IslandButton {
                                objectName: "mediaPreviousButton"
                                glyphObjectName: "mediaPreviousActionLabel"
                                text: Media.canPrev ? qsTr("Previous track") : qsTr("Back 10 seconds")
                                glyph: !Media.canPrev && expandedMediaContent.seekAvailable ? "−10s" : "󰒮"
                                font.pixelSize: !Media.canPrev && expandedMediaContent.seekAvailable ? 12 : 20
                                enabled: islandWindow.hasMedia && (Media.canPrev || expandedMediaContent.seekAvailable)
                                onClicked: {
                                    if (Media.canPrev) Media.previous();
                                    else Media.setPosition(Media.position - 10);
                                }
                            }
                            IslandButton {
                                objectName: "mediaPlayButton"
                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 36
                                prominent: true
                                enabled: islandWindow.hasMedia && Media.canToggle
                                text: Media.isPlaying ? qsTr("Pause") : qsTr("Play")
                                glyph: Media.isPlaying ? "󰏤" : "󰐊"
                                font.pixelSize: 22
                                onClicked: Media.togglePlaying()
                            }
                            IslandButton {
                                objectName: "mediaNextButton"
                                glyphObjectName: "mediaNextActionLabel"
                                text: Media.canNext ? qsTr("Next track") : qsTr("Forward 10 seconds")
                                glyph: !Media.canNext && expandedMediaContent.seekAvailable ? "+10s" : "󰒭"
                                font.pixelSize: !Media.canNext && expandedMediaContent.seekAvailable ? 12 : 20
                                enabled: islandWindow.hasMedia && (Media.canNext || expandedMediaContent.seekAvailable)
                                onClicked: {
                                    if (Media.canNext) Media.next();
                                    else Media.setPosition(Media.position + 10);
                                }
                            }
                            Item { Layout.fillWidth: true }
                            IslandButton {
                                objectName: "mediaLoopButton"
                                text: Media.activePlayer?.loopState === Media.loopTrack ? qsTr("Repeat track")
                                    : highlighted ? qsTr("Repeat playlist") : qsTr("Repeat off")
                                glyph: Media.activePlayer?.loopState === Media.loopTrack ? "󰑗" : "󰑖"
                                enabled: expandedMediaContent.loopAvailable
                                highlighted: (Media.activePlayer?.loopState ?? Media.loopNone) !== Media.loopNone
                                onClicked: Media.cycleLoop()
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
                revealStart: 0.18
                exitDuration: 230
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
