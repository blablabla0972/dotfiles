pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../theme"

Row {
    id: root
    spacing: 5

    readonly property int focusedWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    // Show five normal workspaces plus any higher-numbered active/special slot.
    readonly property var workspaceIds: {
        var ids = [1, 2, 3, 4, 5];
        var active = Hyprland.workspaces.values;
        for (var i = 0; i < active.length; i++) {
            var wsId = active[i].id;
            if (wsId > 0 && ids.indexOf(wsId) < 0) ids.push(wsId);
        }
        if (root.focusedWsId > 0 && ids.indexOf(root.focusedWsId) < 0)
            ids.push(root.focusedWsId);
        return ids.sort((a, b) => a - b);
    }

    Repeater {
        model: root.workspaceIds

        Rectangle {
            id: wsBadge
            required property int modelData
            readonly property int wsId: modelData
            readonly property bool isCurrent: root.focusedWsId === wsId

            width: isCurrent ? 24 : 8
            height: 8
            radius: 4
            color: isCurrent ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4)

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            HoverHandler { id: wsHover }

            TapHandler {
                onTapped: Hyprland.dispatch("workspace " + wsBadge.wsId)
            }
        }
    }

    // Scroll wheel on workspaces to cycle
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                Hyprland.dispatch("workspace e+1");
            } else if (event.angleDelta.y < 0) {
                Hyprland.dispatch("workspace e-1");
            }
        }
    }
}
