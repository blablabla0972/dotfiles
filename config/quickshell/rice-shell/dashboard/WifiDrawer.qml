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

    property var networks: []
    property string selectedSsid: ""
    property string passwordText: ""
    property string statusMessage: ""
    property bool isConnecting: false
    property bool isScanning: scanProcess.running

    onVisibleChanged: {
        if (visible) {
            scan();
        }
    }

    function scan(): void {
        statusMessage = "Scanning networks...";
        scanProcess.command = ["bash", "-c", "nmcli radio wifi on 2>/dev/null; nmcli -t -f active,ssid,signal,security dev wifi list --rescan yes"];
        scanProcess.running = true;
    }

    Process {
        id: scanProcess
        command: ["nmcli", "-t", "-f", "active,ssid,signal,security", "dev", "wifi", "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lines = text.trim().split("\n");
                    var list = [];
                    var seen = {};
                    for (var i = 0; i < lines.length; i++) {
                        var line = lines[i].trim();
                        if (!line) continue;
                        var parts = line.split(":");
                        if (parts.length >= 4) {
                            var active = (parts[0] === "yes" || parts[0] === "*");
                            var ssid = parts[1].trim();
                            var sig = parseInt(parts[2]) || 0;
                            var sec = parts[3].trim();
                            if (ssid.length > 0 && !seen[ssid]) {
                                seen[ssid] = true;
                                list.push({
                                    active: active,
                                    ssid: ssid,
                                    signal: sig,
                                    security: sec,
                                    secured: sec.length > 0 && sec !== "--"
                                });
                            }
                        }
                    }
                    list.sort(function(a, b) {
                        if (a.active && !b.active) return -1;
                        if (!a.active && b.active) return 1;
                        return b.signal - a.signal;
                    });
                    root.networks = list;
                    root.statusMessage = list.length > 0 ? "" : "No networks found";
                } catch (e) {
                    root.statusMessage = "Scan error";
                }
            }
        }
    }

    Process {
        id: connectProcess
        onExited: (exitCode) => {
            root.isConnecting = false;
            if (exitCode === 0) {
                root.statusMessage = "Connected successfully!";
                root.selectedSsid = "";
                root.passwordText = "";
                root.scan();
            } else {
                root.statusMessage = "Connection failed";
            }
        }
    }

    Process {
        id: disconnectProcess
        onExited: (exitCode) => {
            root.isConnecting = false;
            root.statusMessage = "Disconnected";
            root.scan();
        }
    }

    function connectNetwork(net): void {
        if (net.active) {
            root.isConnecting = true;
            root.statusMessage = "Disconnecting...";
            disconnectProcess.command = ["nmcli", "con", "down", "id", net.ssid];
            disconnectProcess.running = true;
            return;
        }

        if (net.secured && root.passwordText.length === 0 && root.selectedSsid !== net.ssid) {
            root.selectedSsid = net.ssid;
            root.statusMessage = "";
            return;
        }

        root.isConnecting = true;
        root.statusMessage = "Connecting to " + net.ssid + "...";
        if (net.secured && root.passwordText.length > 0) {
            connectProcess.command = ["nmcli", "dev", "wifi", "connect", net.ssid, "password", root.passwordText];
        } else {
            connectProcess.command = ["nmcli", "dev", "wifi", "connect", net.ssid];
        }
        connectProcess.running = true;
    }

    Component.onCompleted: {
        scan();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header: Back button + Title + Refresh
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
                text: "Wi-Fi Networks"
                font.pixelSize: 12
                font.bold: true
                color: Tokens.text_primary
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: refreshHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    font.pixelSize: 13
                    color: root.isScanning ? Tokens.accent : Tokens.text_secondary
                }

                HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.scan() }
            }
        }

        // Empty state indicator
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.networks.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰤮"
                    font.pixelSize: 32
                    color: Tokens.text_secondary
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isScanning ? "Scanning for networks..." : "No Wi-Fi networks found"
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                }
            }
        }

        // Network List View
        ListView {
            id: netListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.networks.length > 0
            clip: true
            spacing: 6
            model: root.networks

            delegate: Rectangle {
                id: netRow
                required property var modelData
                width: netListView.width
                height: isSelectedPasswordRow ? 74 : 36
                radius: 8
                color: modelData.active 
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : (rowHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                border.color: modelData.active 
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.5)
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2)
                border.width: 1

                readonly property bool isSelectedPasswordRow: root.selectedSsid === modelData.ssid && !modelData.active

                Behavior on height {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    // Main Row: Signal Icon + SSID + Security + Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: {
                                var s = netRow.modelData.signal;
                                if (s >= 75) return "󰤨";
                                if (s >= 50) return "󰤥";
                                if (s >= 25) return "󰤢";
                                return "󰤟";
                            }
                            font.pixelSize: 13
                            color: netRow.modelData.active ? Tokens.accent : Tokens.text_secondary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: netRow.modelData.ssid
                            font.pixelSize: 11
                            font.bold: netRow.modelData.active
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: netRow.modelData.secured
                            text: "󰌾"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }

                        Text {
                            visible: netRow.modelData.active
                            text: "󰄲"
                            font.pixelSize: 12
                            color: Tokens.accent
                        }
                    }

                    // Inline Password Field for Secured Network Connection
                    RowLayout {
                        visible: netRow.isSelectedPasswordRow
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            radius: 6
                            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9)
                            border.color: Tokens.outline
                            border.width: 1

                            TextInput {
                                id: passInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                font.pixelSize: 11
                                color: Tokens.text_primary
                                echoMode: TextInput.Password
                                text: root.passwordText
                                onTextChanged: root.passwordText = text
                                onAccepted: root.connectNetwork(netRow.modelData)
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: "Password..."
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                                visible: passInput.text.length === 0
                            }
                        }

                        Rectangle {
                            width: 54
                            height: 26
                            radius: 6
                            color: connectHover.hovered ? Tokens.accent : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.8)

                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.surface
                            }

                            HoverHandler { id: connectHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.connectNetwork(netRow.modelData) }
                        }
                    }
                }

                TapHandler {
                    // Only trigger if not clicking inside password field
                    enabled: !netRow.isSelectedPasswordRow
                    onTapped: root.connectNetwork(netRow.modelData)
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
