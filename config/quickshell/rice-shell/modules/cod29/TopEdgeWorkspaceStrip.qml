pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"

PanelWindow {
    id: stripWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    implicitHeight: 140

    anchors {
        top: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool isStripVisible: false
    property int highlightedWorkspaceId: -1
    property string socketPath: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000";
        var sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
        if (sig) return runtime + "/hypr/" + sig + "/cod29.sock";
        return "/tmp/hypr-cod29.sock";
    }

    visible: isStripVisible || containerBox.y > -containerBox.height

    readonly property var targetMonitor: Hyprland.monitorFor(targetScreen)
    readonly property var activeWorkspace: targetMonitor ? targetMonitor.activeWorkspace : null
    readonly property int focusedWsId: activeWorkspace ? activeWorkspace.id : 0

    // Dynamic list of workspaces ensuring 1..5 exist plus any active ones
    readonly property var workspaceList: {
        var map = {};
        for (var i = 1; i <= 5; i++) {
            map[i] = { id: i, name: String(i), windows: 0, isCurrent: (stripWindow.focusedWsId === i) };
        }
        var all = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        if (all) {
            for (var j = 0; j < all.length; j++) {
                var ws = all[j];
                if (ws && ws.id > 0) {
                    var winCount = (ws.lastIpcObject && ws.lastIpcObject.windows !== undefined)
                        ? Number(ws.lastIpcObject.windows) : 0;
                    map[ws.id] = {
                        id: ws.id,
                        name: ws.name || String(ws.id),
                        windows: winCount,
                        isCurrent: (stripWindow.focusedWsId === ws.id)
                    };
                }
            }
        }
        var list = Object.values(map);
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    function handleIpcMessage(msg: string): void {
        if (!msg) return;
        var parts = msg.split(" ");
        var cmd = parts[0];
        var arg = parts.length > 1 ? parts[1] : "";

        switch (cmd) {
        case "SHOW_STRIP":
            stripWindow.isStripVisible = true;
            syncBoundsTimer.restart();
            break;
        case "HIDE_STRIP":
            stripWindow.isStripVisible = false;
            stripWindow.highlightedWorkspaceId = -1;
            break;
        case "TARGET_CHANGED":
        case "HIGHLIGHT":
            stripWindow.highlightedWorkspaceId = parseInt(arg) || -1;
            break;
        case "RESET":
            stripWindow.isStripVisible = false;
            stripWindow.highlightedWorkspaceId = -1;
            break;
        default:
            console.log("[COD-29 Strip] Unknown IPC command: " + msg);
        }
    }

    function syncCardBounds(): void {
        if (!ipcSocket.connected || !cardsRepeater) return;
        var bounds = [];
        var list = stripWindow.workspaceList;
        for (var i = 0; i < cardsRepeater.count && i < list.length; i++) {
            var item = cardsRepeater.itemAt(i);
            if (item) {
                var point = item.mapToItem(null, 0, 0);
                bounds.push({
                    id: list[i].id,
                    x: Math.round(point.x),
                    y: Math.round(point.y),
                    w: Math.round(item.width),
                    h: Math.round(item.height)
                });
            }
        }
        ipcSocket.write("REGISTER_BOUNDS " + JSON.stringify(bounds) + "\n");
    }

    function onCardHovered(wsId: int): void {
        if (ipcSocket.connected) {
            ipcSocket.write("CARD_HOVER " + wsId + "\n");
        }
    }

    function onCardLeft(wsId: int): void {
        if (ipcSocket.connected) {
            ipcSocket.write("CARD_LEAVE " + wsId + "\n");
        }
    }

    // UNIX Domain Socket IPC Connection
    Socket {
        id: ipcSocket
        path: stripWindow.socketPath
        connected: true

        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                stripWindow.handleIpcMessage(data.trim());
            }
        }

        onConnectionStateChanged: {
            if (connected) {
                console.log("[COD-29 Strip] Connected to IPC socket: " + stripWindow.socketPath);
                write("STRIP_READY\n");
                syncBoundsTimer.restart();
            }
        }

        onError: error => {
            retryTimer.restart();
        }
    }

    Timer {
        id: retryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!ipcSocket.connected) {
                ipcSocket.connected = false;
                ipcSocket.connected = true;
            }
        }
    }

    Timer {
        id: syncBoundsTimer
        interval: 50
        repeat: false
        onTriggered: stripWindow.syncCardBounds()
    }

    // Main Floating Strip Container
    Rectangle {
        id: containerBox
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 48, cardsLayout.implicitWidth + 36)
        height: 116
        y: stripWindow.isStripVisible ? 8 : -130
        opacity: stripWindow.isStripVisible ? 1.0 : 0.0
        radius: 20
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Math.max(0.92, Tokens.panelOpacity))
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
        border.width: 1
        clip: true

        Behavior on y {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: cardsLayout
            anchors.centerIn: parent
            spacing: 10

            Repeater {
                id: cardsRepeater
                model: stripWindow.workspaceList

                delegate: Rectangle {
                    id: cardItem
                    required property var modelData
                    readonly property int wsId: modelData.id
                    readonly property bool isTarget: stripWindow.highlightedWorkspaceId === wsId
                    readonly property bool isCurrent: modelData.isCurrent
                    readonly property int winCount: modelData.windows

                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 90
                    radius: 14

                    color: isTarget
                        ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.28)
                        : (isCurrent
                            ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.85)
                            : Qt.rgba(Tokens.surface_low.r, Tokens.surface_low.g, Tokens.surface_low.b, 0.65))

                    border.color: isTarget
                        ? Tokens.accent
                        : (isCurrent
                            ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.6)
                            : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25))
                    border.width: isTarget ? 2 : 1
                    scale: isTarget ? 1.05 : 1.0

                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: cardItem.modelData.name
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            color: cardItem.isTarget ? Tokens.accent : Tokens.text_primary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: cardItem.isCurrent ? "Current" : (cardItem.winCount + (cardItem.winCount === 1 ? " win" : " wins"))
                            font.pixelSize: 11
                            color: cardItem.isCurrent ? Tokens.text_secondary : (cardItem.isTarget ? Tokens.accent : Tokens.text_secondary)
                        }
                    }

                    HoverHandler {
                        id: cardHover
                        onHoveredChanged: {
                            if (hovered) {
                                stripWindow.onCardHovered(cardItem.wsId);
                            } else {
                                stripWindow.onCardLeft(cardItem.wsId);
                            }
                        }
                    }
                }
            }
        }
    }
}
