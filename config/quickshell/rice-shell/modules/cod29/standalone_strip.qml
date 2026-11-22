pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            TopEdgeWorkspaceStrip {
                required property var modelData
                targetScreen: modelData
            }
        }
    }
}
