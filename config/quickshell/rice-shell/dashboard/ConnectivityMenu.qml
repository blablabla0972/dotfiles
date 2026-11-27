pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Item {
    id: root
    required property ShellScreen targetScreen
    property Item anchorItem: null
    property string page: ""
    property bool opened: false
    property real reveal: opened ? 1 : 0
    Behavior on reveal {
        id: transition
        SmoothedAnimation {
            velocity: transition.targetValue === 1 ? 7 : 11
            maximumEasingTime: 35
        }
    }
    onRevealChanged: if (!opened && reveal === 0) releasePage()
    onAnchorItemChanged: if (!anchorItem && opened) close()

    function open(type: string, anchor: Item): void {
        if ((type !== "wifi" && type !== "bluetooth") || !anchor || !anchor.visible) {
            close();
            return;
        }
        if (opened && anchorItem === anchor && page === type) {
            close();
            return;
        }
        anchorItem = anchor;
        page = type;
        opened = true;
    }

    function close(): void {
        opened = false;
        if (reveal === 0) releasePage();
    }

    function releasePage(): void {
        page = "";
        anchorItem = null;
    }

    // Handle the menu and click-away on one surface, leaving the bar accessible.
    PanelWindow {
        id: popup
        visible: root.opened || root.reveal > 0
        screen: root.targetScreen
        anchors.top: true
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "rice-connectivity-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        readonly property var bar: root.anchorItem?.QsWindow.window ?? null
        margins.top: bar?.height ?? 0
        readonly property real anchorCenter: {
            const item = root.anchorItem;
            if (!item || !bar) return 0;
            return item.mapToItem(bar.contentItem, item.width / 2, 0).x;
        }
        mask: root.opened ? null : emptyInput
        Region { id: emptyInput }

        Connections {
            target: root.anchorItem
            function onVisibleChanged(): void {
                if (!root.anchorItem.visible) root.close();
            }
        }

        Shortcut {
            sequence: "Escape"
            enabled: root.opened
            context: Qt.ApplicationShortcut
            onActivated: {
                if (!connectivity.handleEscape()) root.close();
            }
        }

        MouseArea {
            id: backdrop
            anchors.fill: parent
            enabled: root.opened
            acceptedButtons: Qt.AllButtons
            onPressed: (mouse) => {
                const p = connectivity.mapFromItem(backdrop, mouse.x, mouse.y);
                mouse.accepted = !connectivity.contains(p);
                if (mouse.accepted) root.close();
            }
        }

        ConnectivityCenter {
            id: connectivity
            width: Math.min(implicitWidth, Math.max(1, parent.width - 24))
            height: Math.min(implicitHeight, Math.max(1, parent.height - y - 8))
            x: Math.round(Math.max(12, Math.min(popup.anchorCenter - width / 2, parent.width - width - 12)))
            y: 6
            enabled: root.opened
            opacity: root.reveal * (2 - root.reveal)
            transform: Scale {
                origin.x: Math.max(0, Math.min(connectivity.width, popup.anchorCenter - connectivity.x))
                origin.y: 0
                xScale: 0.965 + 0.035 * root.reveal
                yScale: 0.93 + 0.07 * root.reveal
            }
            currentPage: root.page
            drawerOpen: popup.visible
            compactMenu: true
            onCloseRequested: root.close()
            onRequestSettings: (route) => {
                root.close();
                root.settingsRequested(route);
            }
        }
    }

    Binding {
        target: popup.bar
        property: "connectivityMenuOpen"
        value: true
        when: popup.visible && popup.bar !== null && ("connectivityMenuOpen" in popup.bar)
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged(): void {
            if (root.opened && Hyprland.focusedMonitor && Hyprland.focusedMonitor.name !== root.targetScreen.name)
                root.close();
        }
    }

    signal settingsRequested(string route)
}
