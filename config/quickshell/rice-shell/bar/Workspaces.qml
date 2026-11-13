pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"

Row {
    id: root
    spacing: 5

    required property var targetMonitor
    required property var workspaceList
    readonly property var activeWorkspace: targetMonitor ? targetMonitor.activeWorkspace : null
    readonly property int focusedWsId: activeWorkspace ? activeWorkspace.id : 0
    // Hyprland's workspace model includes persistent 1–5 and active additions; named workspaces have negative IDs.
    readonly property var workspaceItems: {
        if (!targetMonitor) return [];
        var items = [];
        var all = workspaceList || [];
        for (var i = 0; i < all.length; i++) {
            var workspace = all[i];
            if (workspace && workspace.id > 0 && workspace.monitor
                    && workspace.monitor.name === targetMonitor.name)
                items.push(workspace);
        }
        if (activeWorkspace && activeWorkspace.id > 0
                && items.every(workspace => workspace.id !== activeWorkspace.id))
            items.push(activeWorkspace);
        return items.sort((a, b) => a.id - b.id);
    }

    function activateWorkspace(workspace: var): void {
        if (!targetMonitor || !workspace || workspace.id <= 0 || !workspace.monitor
                || workspace.monitor.name !== targetMonitor.name)
            return;
        if (typeof workspace.activate === "function") workspace.activate();
    }

    function cycleWorkspace(direction: int): void {
        var items = workspaceItems;
        if (!targetMonitor || items.length === 0 || direction === 0) return;
        var currentIndex = items.findIndex(workspace => workspace.id === focusedWsId);
        if (currentIndex < 0) currentIndex = direction > 0 ? -1 : 0;
        var nextIndex = (currentIndex + (direction > 0 ? 1 : -1) + items.length) % items.length;
        activateWorkspace(items[nextIndex]);
    }

    Repeater {
        model: root.workspaceItems

        Rectangle {
            id: wsBadge
            required property var modelData
            readonly property int wsId: modelData.id
            readonly property bool isCurrent: root.focusedWsId === wsId
            readonly property bool isOccupied: modelData.lastIpcObject
                ? Number(modelData.lastIpcObject.windows) > 0 : false

            width: isCurrent ? 24 : (isOccupied ? 12 : 8)
            height: 8
            radius: 4
            color: isCurrent ? Tokens.accent : isOccupied
                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.55)
                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            HoverHandler { id: wsHover }

            TapHandler {
                onTapped: root.activateWorkspace(wsBadge.modelData)
            }
        }
    }

    // Scroll wheel on workspaces to cycle
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y !== 0) root.cycleWorkspace(event.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
