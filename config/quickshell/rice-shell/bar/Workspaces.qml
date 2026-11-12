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

    Repeater {
        model: 6

        Rectangle {
            id: wsBadge
            required property int index
            readonly property int wsId: index + 1
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
