pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

PanelWindow {
    id: powerWindow

    required property ShellScreen targetScreen
    screen: targetScreen
    color: "transparent"
    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string pendingAction: ""
    property int confirmationSeconds: 0
    property string statusMessage: ""

    mask: Region {
        item: powerWindow.visible ? overlay : null
    }

    function toggle(): void {
        if (visible) dismissMenu();
        else showMenu();
    }

    function showMenu(): void {
        confirmationTimer.stop();
        pendingAction = "";
        statusMessage = "";
        visible = true;
        keyTarget.forceActiveFocus();
    }

    function dismissMenu(): void {
        confirmationTimer.stop();
        pendingAction = "";
        statusMessage = "";
        visible = false;
    }

    function activate(actionId: string): void {
        if (actionId === "lock" || actionId === "sleep") {
            runAction(actionId);
            return;
        }

        if (pendingAction !== actionId) {
            pendingAction = actionId;
            confirmationSeconds = 5;
            statusMessage = "Click again to confirm within 5 seconds.";
            confirmationTimer.restart();
            return;
        }

        confirmationTimer.stop();
        pendingAction = "";
        statusMessage = "";
        runAction(actionId);
    }

    function runAction(actionId: string): void {
        if (actionProcess.running) {
            statusMessage = "Another action is already running.";
            return;
        }

        confirmationTimer.stop();
        pendingAction = "";

        const commands = {
            "lock": ["hyprlock"],
            "sleep": ["systemctl", "suspend"],
            "logout": ["uwsm", "stop"],
            "reboot": ["systemctl", "reboot"],
            "shutdown": ["systemctl", "poweroff"]
        };

        if (!commands[actionId]) return;
        actionProcess.command = commands[actionId];
        visible = false;
        actionProcess.running = true;
    }

    Timer {
        id: confirmationTimer
        interval: 1000
        repeat: true

        onTriggered: {
            powerWindow.confirmationSeconds--;
            if (powerWindow.confirmationSeconds <= 0) {
                confirmationTimer.stop();
                powerWindow.pendingAction = "";
                powerWindow.statusMessage = "Confirmation cancelled.";
            } else {
                powerWindow.statusMessage = "Click again to confirm · "
                    + powerWindow.confirmationSeconds + "s";
            }
        }
    }

    Process {
        id: actionProcess
        command: []

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                powerWindow.statusMessage = "Action failed (exit code " + exitCode + ").";
                powerWindow.visible = true;
                keyTarget.forceActiveFocus();
            }
        }
    }

    Item {
        id: overlay
        anchors.fill: parent
        visible: powerWindow.visible

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: powerWindow.dismissMenu()
        }

        Item {
            id: keyTarget
            anchors.fill: parent
            focus: powerWindow.visible

            Keys.onEscapePressed: (event) => {
                event.accepted = true;
                powerWindow.dismissMenu();
            }
        }

        Rectangle {
            id: panel
            z: 2
            anchors.centerIn: parent
            width: Math.min(780, parent.width - 32)
            height: content.implicitHeight + 36
            radius: 22
            color: Tokens.surface
            border.width: 1
            border.color: Tokens.outline

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                RowLayout {
                    id: actionGrid
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { id: "lock", icon: "󰌾", title: "Lock", danger: false },
                            { id: "sleep", icon: "󰒲", title: "Sleep", danger: false },
                            { id: "logout", icon: "󰍃", title: "Log out", danger: true },
                            { id: "reboot", icon: "󰜉", title: "Reboot", danger: true },
                            { id: "shutdown", icon: "󰐥", title: "Shutdown", danger: true }
                        ]

                        delegate: Rectangle {
                            id: actionTile
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredWidth: 145
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 146
                            radius: 16
                            scale: hovered ? 1.045 : 1.0
                            z: hovered ? 2 : 0
                            color: armed
                                ? (modelData.danger ? Tokens.danger : Tokens.accent)
                                : (hovered ? Tokens.accent : Tokens.surface_high)
                            border.width: hovered || armed ? 2 : 1
                            border.color: armed ? Tokens.danger : (hovered ? Tokens.accent : Tokens.outline)

                            readonly property bool armed: powerWindow.pendingAction === modelData.id
                            readonly property bool hovered: actionMouse.containsMouse

                            Behavior on scale {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 42

                                    Text {
                                        anchors.centerIn: parent
                                        text: actionTile.armed ? "󰄬" : actionTile.modelData.icon
                                        color: actionTile.armed && actionTile.modelData.danger
                                            ? Tokens.background
                                            : (actionTile.hovered ? Tokens.on_accent : Tokens.accent)
                                        font.pixelSize: 40
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: actionTile.modelData.title
                                    color: actionTile.armed && actionTile.modelData.danger
                                        ? Tokens.background
                                        : (actionTile.hovered || actionTile.armed ? Tokens.on_accent : Tokens.text_primary)
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: actionTile.armed
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "Click again to confirm"
                                    color: actionTile.modelData.danger ? Tokens.background : Tokens.on_accent
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: powerWindow.activate(actionTile.modelData.id)
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: powerWindow.statusMessage.length > 0
                    text: powerWindow.statusMessage
                    color: powerWindow.pendingAction.length > 0 ? Tokens.danger
                        : Tokens.text_secondary
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
