pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../theme"
import "WindowSwitcherState.js" as State

PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen
    visible: false
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "rice-window-switcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string origin: ""
    property string originWorkspace: ""
    property string selectedAddress: ""
    readonly property var windows: visible || origin
        ? State.orderedWindows(Hyprland.toplevels.values, origin, originWorkspace) : []
    readonly property int selectedIndex: windows.findIndex(window => window.address === selectedAddress)

    function open(direction: int): void {
        originWorkspace = Hyprland.focusedWorkspace?.name ?? "";
        origin = Hyprland.activeToplevel?.address ?? "";
        visible = true;
        selectedAddress = State.stepAddress(windows, origin, direction);
        backdrop.forceActiveFocus();
        entrance.restart();
    }

    function step(direction: int): void {
        selectedAddress = State.stepAddress(windows, selectedAddress, direction);
    }

    function dismiss(): void {
        if (!visible) return;
        visible = false;
        origin = "";
        originWorkspace = "";
        selectedAddress = "";
    }

    function accept(address: string): void {
        const commands = State.activationCommands(windows, address, Hyprland.usingLua);
        dismiss();
        // Unmap the keyboard-exclusive layer before asking Hyprland to focus a client.
        if (commands.length) Qt.callLater(() => commands.forEach(command => Hyprland.dispatch(command)));
    }

    onWindowsChanged: {
        if (visible && !windows.some(window => window.address === selectedAddress))
            selectedAddress = windows[0]?.address ?? "";
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        focus: true
        color: Qt.rgba(Tokens.background.r, Tokens.background.g, Tokens.background.b, 0.42)

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Tab:
                root.step(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                break;
            case Qt.Key_Backtab:
            case Qt.Key_Left:
                root.step(-1);
                break;
            case Qt.Key_Right:
                root.step(1);
                break;
            case Qt.Key_Up:
                root.step(-grid.columns);
                break;
            case Qt.Key_Down:
                root.step(grid.columns);
                break;
            case Qt.Key_Escape:
                root.dismiss();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.accept(root.selectedAddress);
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        TapHandler {
            onTapped: (point) => {
                if (!panel.contains(panel.mapFromItem(backdrop, point.position))) root.dismiss();
            }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(backdrop.width - 32, grid.columns * 420 + 36)
            height: Math.min(body.implicitHeight + 36, backdrop.height - 32)
            radius: 22
            color: Tokens.surface
            border.color: Tokens.outline

            ParallelAnimation {
                id: entrance
                NumberAnimation { target: panel; property: "opacity"; from: 0; to: 1; duration: 120 }
                NumberAnimation {
                    target: panel; property: "scale"; from: 0.97; to: 1; duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Text {
                    visible: !root.windows.length
                    Layout.fillWidth: true
                    text: "No open windows"
                    color: Tokens.text_secondary
                    font.pixelSize: 14
                }

                GridView {
                    id: grid
                    readonly property int columns: Math.min(3, Math.max(1, root.windows.length),
                        Math.max(1, Math.floor((backdrop.width - 68) / 310)))
                    visible: root.windows.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: Math.min(3, Math.ceil(count / columns)) * cellHeight
                    cellWidth: Math.floor(width / columns)
                    cellHeight: Math.round(cellWidth * 9 / 16) + 45
                    model: root.windows
                    currentIndex: root.selectedIndex
                    clip: true
                    keyNavigationEnabled: false
                    boundsBehavior: Flickable.StopAtBounds
                    Accessible.name: "Open windows"
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        id: row
                        required property HyprlandToplevel modelData
                        required property int index
                        readonly property bool selected: index === root.selectedIndex
                        readonly property bool wasActive: modelData.address === root.origin
                        readonly property Toplevel toplevel: modelData.wayland
                        readonly property string appId: toplevel?.appId || modelData.lastIpcObject.class || ""
                        readonly property var app: appId ? DesktopEntries.heuristicLookup(appId) : null
                        readonly property string title: modelData.title || app?.name || appId || "Untitled window"
                        readonly property string workspace: modelData.workspace?.name || ""

                        width: grid.cellWidth - 8
                        height: grid.cellHeight - 8
                        radius: 12
                        color: selected ? Qt.tint(Tokens.surface_high, Qt.alpha(Tokens.accent, 0.16))
                            : rowHover.hovered ? Tokens.surface_high : Tokens.surface
                        border.color: selected ? Tokens.accent : Tokens.outline
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Accessible.role: Accessible.ListItem
                        Accessible.name: title + ", workspace " + workspace + (wasActive ? ", active window" : "")
                        Accessible.selected: selected

                        HoverHandler { id: rowHover }
                        TapHandler { onTapped: root.accept(row.modelData.address) }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 5

                            Rectangle {
                                id: previewFrame
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Tokens.background
                                radius: 6

                                ScreencopyView {
                                    id: preview
                                    anchors.centerIn: parent
                                    constraintSize: Qt.size(previewFrame.width - 8, previewFrame.height - 8)
                                    captureSource: root.visible ? row.toplevel : null
                                    paintCursor: false
                                    visible: hasContent
                                    // shortcut: one frame per tile, add live updates if requested.
                                    onCaptureSourceChanged: {
                                        if (captureSource) Qt.callLater(() => {
                                            if (preview.captureSource) preview.captureFrame();
                                        });
                                    }
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 44
                                    height: 44
                                    visible: !preview.hasContent
                                    source: appIcon.source
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Image {
                                    id: appIcon
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: Quickshell.iconPath(row.app?.icon || row.appId || "application-x-executable",
                                        "application-x-executable")
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.title
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Tokens.text_primary
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.maximumWidth: 50
                                    text: row.workspace ? "WS " + row.workspace : ""
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: row.wasActive ? Tokens.accent : Tokens.text_secondary
                                    font.pixelSize: 12
                                }
                            }

                        }
                    }
                }
            }
        }
    }
}
