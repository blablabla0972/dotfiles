pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Rectangle {
    id: root

    anchors.fill: parent
    radius: 22
    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.96)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
    border.width: 1
    clip: true

    signal closeRequested()

    property var devices: []
    property bool isScanning: false
    property string statusMessage: ""
    property bool isConnecting: false

    function refresh(): void {
        statusMessage = "Loading devices...";
        listProcess.running = true;
    }

    Process {
        id: listProcess
        command: ["bluetoothctl", "devices"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lines = text.trim().split("\n");
                    var list = [];
                    var seen = {};
                    for (var i = 0; i < lines.length; i++) {
                        var line = lines[i].trim();
                        if (!line.startsWith("Device ")) continue;
                        var parts = line.split(" ");
                        if (parts.length >= 3) {
                            var mac = parts[1].trim();
                            var name = parts.slice(2).join(" ").trim();
                            if (mac.length > 0 && !seen[mac]) {
                                seen[mac] = true;
                                list.push({
                                    mac: mac,
                                    name: name,
                                    connected: false
                                });
                            }
                        }
                    }
                    root.devices = list;
                    root.statusMessage = list.length > 0 ? "" : "No Bluetooth devices found";
                } catch (e) {
                    root.statusMessage = "Error reading devices";
                }
            }
        }
    }

    Process {
        id: actionProcess
        onExited: (exitCode) => {
            root.isConnecting = false;
            if (exitCode === 0) {
                root.statusMessage = "Success";
                root.refresh();
            } else {
                root.statusMessage = "Action failed";
            }
        }
    }

    Process {
        id: scanProcess
        onExited: (exitCode) => {
            root.refresh();
        }
    }

    function toggleScan(): void {
        root.isScanning = !root.isScanning;
        scanProcess.command = ["bluetoothctl", "scan", root.isScanning ? "on" : "off"];
        scanProcess.running = true;
        root.statusMessage = root.isScanning ? "Scanning for devices..." : "Scan stopped";
    }

    function connectDevice(dev): void {
        root.isConnecting = true;
        root.statusMessage = dev.connected ? "Disconnecting..." : "Connecting to " + dev.name + "...";
        actionProcess.command = ["bluetoothctl", dev.connected ? "disconnect" : "connect", dev.mac];
        actionProcess.running = true;
    }

    function getDeviceIcon(name): string {
        var lower = name.toLowerCase();
        if (lower.indexOf("head") >= 0 || lower.indexOf("bud") >= 0 || lower.indexOf("airpod") >= 0 || lower.indexOf("wh-") >= 0) {
            return "󰋋";
        }
        if (lower.indexOf("speaker") >= 0 || lower.indexOf("sound") >= 0) {
            return "󰓃";
        }
        if (lower.indexOf("keyboard") >= 0 || lower.indexOf("key") >= 0) {
            return "󰌌";
        }
        if (lower.indexOf("mouse") >= 0 || lower.indexOf("mx") >= 0) {
            return "󰍽";
        }
        if (lower.indexOf("phone") >= 0 || lower.indexOf("galaxy") >= 0 || lower.indexOf("pixel") >= 0) {
            return "󰏲";
        }
        return "󰂯";
    }

    Component.onCompleted: {
        refresh();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header: Back button + Title + Scan button
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: backHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)

                Text {
                    anchors.centerIn: parent
                    text: "󰁍"
                    font.pixelSize: 14
                    color: Tokens.text_primary
                }

                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.closeRequested() }
            }

            Text {
                text: "Bluetooth Devices"
                font.pixelSize: 12
                font.bold: true
                color: Tokens.text_primary
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: root.isScanning 
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.3)
                    : (scanHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7))

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    font.pixelSize: 13
                    color: root.isScanning ? Tokens.accent : Tokens.text_secondary
                }

                HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.toggleScan() }
            }
        }

        // Empty state indicator
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.devices.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰂲"
                    font.pixelSize: 32
                    color: Tokens.text_secondary
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isScanning ? "Scanning for devices..." : "No Bluetooth devices found"
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                }
            }
        }

        // Devices List View
        ListView {
            id: devListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.devices.length > 0
            clip: true
            spacing: 6
            model: root.devices

            delegate: Rectangle {
                id: devRow
                required property var modelData
                width: devListView.width
                height: 38
                radius: 8
                color: devRow.modelData.connected 
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : (rowHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                border.color: devRow.modelData.connected 
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.5)
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2)
                border.width: 1

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: root.getDeviceIcon(devRow.modelData.name)
                        font.pixelSize: 14
                        color: devRow.modelData.connected ? Tokens.accent : Tokens.text_secondary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: devRow.modelData.name
                            font.pixelSize: 11
                            font.bold: devRow.modelData.connected
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: devRow.modelData.connected ? "Connected" : devRow.modelData.mac
                            font.pixelSize: 9
                            color: devRow.modelData.connected ? Tokens.accent : Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        width: 50
                        height: 22
                        radius: 6
                        color: btnHover.hovered ? Tokens.accent : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                        border.color: Tokens.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: devRow.modelData.connected ? "Disconnect" : "Connect"
                            font.pixelSize: 9
                            font.bold: true
                            color: btnHover.hovered ? Tokens.surface : Tokens.accent
                        }

                        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.connectDevice(devRow.modelData) }
                    }
                }
            }
        }

        // Status Message Footer
        Text {
            Layout.fillWidth: true
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            font.pixelSize: 10
            color: Tokens.accent
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
