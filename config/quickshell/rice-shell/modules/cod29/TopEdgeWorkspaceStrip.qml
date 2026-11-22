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
    implicitHeight: stripHeight + topInset

    anchors {
        top: true
        left: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "cod29-workspace-strip"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool isStripVisible: false
    property int highlightedWorkspaceId: -1
    property point dragPointer: Qt.point(0, 0)
    property point dragAnchor: Qt.point(0.5, 0.5)
    property var dropBox: null
    property var wallpapers: ({})
    property string draggedAddress: ""
    readonly property var draggedWindow: draggedAddress
        ? Hyprland.toplevels.values.find(window => String(window.address).replace(/^0x/, "") === draggedAddress)
        : null
    property string socketPath: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000";
        var sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
        if (sig) return runtime + "/hypr/" + sig + "/cod29.sock";
        return "/tmp/hypr-cod29.sock";
    }

    visible: isStripVisible
    mask: Region {}

    readonly property var targetMonitor: Hyprland.monitorFor(targetScreen)
    readonly property int stripHeight: 216
    readonly property int topInset: Math.max(0, targetMonitor?.lastIpcObject?.reserved?.[1] ?? 0)
    readonly property var activeWorkspace: targetMonitor ? targetMonitor.activeWorkspace : null
    readonly property int focusedWsId: activeWorkspace ? activeWorkspace.id : 0
    onTopInsetChanged: syncBoundsTimer.restart()

    // Dynamic list of workspaces ensuring 1..5 exist plus any active ones
    readonly property var workspaceList: {
        var map = {};
        for (var i = 1; i <= 5; i++) {
            map[i] = { id: i, name: String(i), workspace: null };
        }
        var all = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        if (all) {
            for (var j = 0; j < all.length; j++) {
                var ws = all[j];
                if (ws && ws.id > 0) {
                    map[ws.id] = {
                        id: ws.id,
                        name: ws.name || String(ws.id),
                        workspace: ws
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
            stripWindow.draggedAddress = arg;
            stripWindow.isStripVisible = true;
            Hyprland.refreshToplevels();
            wallpaperQuery.running = true;
            syncBoundsTimer.restart();
            break;
        case "HIDE_STRIP":
        case "RESET":
            stripWindow.isStripVisible = false;
            stripWindow.highlightedWorkspaceId = -1;
            stripWindow.dropBox = null;
            stripWindow.draggedAddress = "";
            break;
        case "TARGET_CHANGED":
        case "HIGHLIGHT":
            stripWindow.highlightedWorkspaceId = parseInt(arg) || -1;
            stripWindow.dropBox = null;
            break;
        case "DROP_BOX":
            stripWindow.dropBox = parts.length === 6 ? {
                id: Number(arg),
                rect: Qt.rect(Number(parts[2]), Number(parts[3]), Number(parts[4]), Number(parts[5]))
            } : null;
            break;
        case "DRAG_POINTER":
            stripWindow.dragAnchor = parts.length === 5 ? Qt.point(Number(parts[3]), Number(parts[4])) : Qt.point(0.5, 0.5);
            stripWindow.dragPointer = Qt.point(Number(arg), Number(parts[2]));
            break;
        default:
            console.log("[COD-29 Strip] Unknown IPC command: " + msg);
        }
    }

    function syncCardBounds(): void {
        if (!ipcSocket.connected || !stripWindow.isStripVisible || !targetMonitor) return;
        var bounds = [];
        var list = stripWindow.workspaceList;
        for (var i = 0; i < cardsRepeater.count && i < list.length; i++) {
            var item = cardsRepeater.itemAt(i);
            if (item) {
                var point = item.mapToItem(null, 0, 0);
                var viewport = item.preview.viewport;
                var offset = item.preview.mapToItem(null, viewport.x, viewport.y);
                bounds.push({
                    id: list[i].id,
                    x: Math.round(targetMonitor.x + point.x),
                    y: Math.round(targetMonitor.y + point.y),
                    w: Math.round(item.width),
                    h: Math.round(item.height),
                    preview: [targetMonitor.x + offset.x, targetMonitor.y + offset.y,
                              viewport.width, viewport.height].map(value => Number(value.toFixed(3)))
                });
            }
        }
        ipcSocket.write("REGISTER_BOUNDS " + JSON.stringify(bounds) + "\n");
    }

    Process {
        id: wallpaperQuery
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const wallpapers = {};
                for (const line of text.split("\n")) {
                    const match = line.match(/^(?::\s*)?([^:]+):.*currently displaying: image: (.+)$/);
                    if (match && match[2].startsWith("/"))
                        wallpapers[match[1].trim()] = "file://" + match[2].split("/").map(encodeURIComponent).join("/");
                }
                stripWindow.wallpapers = wallpapers;
            }
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
        height: stripWindow.stripHeight - 16
        y: stripWindow.topInset + 8
        opacity: stripWindow.isStripVisible ? 1.0 : 0.0
        radius: 20
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Math.max(0.92, Tokens.panelOpacity))
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
        border.width: 1
        clip: true

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
                onCountChanged: syncBoundsTimer.restart()

                delegate: Rectangle {
                    id: cardItem
                    property alias preview: workspacePreview
                    required property var modelData
                    readonly property int wsId: modelData.id
                    readonly property bool isTarget: stripWindow.highlightedWorkspaceId === wsId
                    readonly property bool isCurrent: stripWindow.focusedWsId === wsId
                    readonly property var workspace: modelData.workspace

                    Layout.preferredWidth: Math.min(296, (containerBox.parent.width - 84 - (cardsRepeater.count - 1) * cardsLayout.spacing) / cardsRepeater.count)
                    Layout.preferredHeight: containerBox.height - 16
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
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 3

                        WorkspacePreview {
                            id: workspacePreview
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            workspace: cardItem.workspace
                            strip: stripWindow
                            live: cardItem.isTarget
                            dropRect: stripWindow.dropBox?.id === cardItem.wsId ? stripWindow.dropBox.rect : null
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: cardItem.modelData.name
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: cardItem.isTarget ? Tokens.accent : Tokens.text_primary
                        }
                    }
                }
            }
        }
    }
}
