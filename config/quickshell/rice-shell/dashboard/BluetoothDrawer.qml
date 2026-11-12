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
    property var discoveredMacs: ({})
    property bool isScanning: false
    property string statusMessage: ""
    property string actionMessage: ""
    property bool isConnecting: false
    property string activeDeviceMac: ""
    property string activeDeviceName: ""
    property bool activeDevicePaired: false
    property bool disconnecting: false
    property bool agentReady: false
    property string actionStage: ""
    property string pairingPromptType: ""
    property string pairingPromptText: ""
    property string pairingInputText: ""
    property int agentOutputOffset: 0

    onVisibleChanged: {
        if (visible) {
            actionMessage = "";
            startScan();
            refresh();
            ensureAgent();
        } else {
            isScanning = false;
            scanProcess.running = false;
            if (!isConnecting && agentProcess.running) agentProcess.write("quit\n");
        }
    }

    function refresh(): void {
        if (listProcess.running || pairedProcess.running || connectedProcess.running) return;
        listProcess.running = true;
    }

    function addressVariant(first, second): bool {
        var a = first.split(":");
        var b = second.split(":");
        if (a.length !== 6 || b.length !== 6) return false;
        var changedOctets = 0;
        var difference = 0;
        for (var i = 0; i < 6; i++) {
            var left = parseInt(a[i], 16);
            var right = parseInt(b[i], 16);
            if (left !== right) {
                changedOctets++;
                difference = Math.abs(left - right);
            }
        }
        return changedOctets === 1 && difference <= 4;
    }

    function collapseAddressVariants(list) {
        var result = [];
        for (var i = 0; i < list.length; i++) {
            var device = list[i];
            var duplicateIndex = -1;
            for (var j = 0; j < result.length; j++) {
                var existing = result[j];
                if (device.name.toLowerCase() === existing.name.toLowerCase() && addressVariant(device.mac, existing.mac)) {
                    duplicateIndex = j;
                    break;
                }
            }
            if (duplicateIndex < 0) {
                result.push(device);
                continue;
            }
            var previous = result[duplicateIndex];
            var deviceScore = (device.connected ? 1000 : 0) + (device.paired ? 100 : 0) + (root.discoveredMacs[device.mac.toUpperCase()] ? 1 : 0);
            var previousScore = (previous.connected ? 1000 : 0) + (previous.paired ? 100 : 0) + (root.discoveredMacs[previous.mac.toUpperCase()] ? 1 : 0);
            if (deviceScore > previousScore) result[duplicateIndex] = device;
        }
        return result;
    }

    function startScan(): void {
        if (scanProcess.running) return;
        discoveredMacs = ({});
        isScanning = true;
        statusMessage = "Scanning for devices...";
        scanProcess.command = ["bluetoothctl", "--timeout", "8", "scan", "on"];
        scanProcess.running = true;
    }

    function toggleScan(): void {
        if (isScanning) {
            isScanning = false;
            scanProcess.running = false;
            refresh();
        } else {
            startScan();
        }
    }

    function ensureAgent(): void {
        if (!agentProcess.running) agentProcess.running = true;
    }

    function beginDeviceAction(): void {
        if (!root.isConnecting || !root.agentReady) return;
        if (root.disconnecting) {
            root.actionStage = "disconnect";
            agentProcess.write("disconnect " + root.activeDeviceMac + "\n");
        } else if (root.activeDevicePaired) {
            root.actionStage = "connect";
            agentProcess.write("trust " + root.activeDeviceMac + "\nconnect " + root.activeDeviceMac + "\n");
        } else {
            root.actionStage = "pair";
            agentProcess.write("pair " + root.activeDeviceMac + "\n");
        }
    }

    function finishDeviceAction(message): void {
        root.isConnecting = false;
        root.activeDeviceMac = "";
        root.actionStage = "";
        root.pairingPromptType = "";
        root.pairingInputText = "";
        root.actionMessage = message;
        root.refresh();
    }

    function handleAgentOutput(value): void {
        var fresh = value.slice(root.agentOutputOffset);
        root.agentOutputOffset = value.length;
        if (fresh.length === 0) return;
        var output = fresh.replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "\n");

        if (/Default agent request successful/i.test(output)) {
            root.agentReady = true;
            if (root.actionStage === "waiting-agent") root.beginDeviceAction();
        }

        var passkey = output.match(/Confirm passkey\s+(\d{6})/i);
        if (passkey) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Confirm that " + passkey[1] + " appears on both devices.";
        } else if (/Accept pairing\s*\(yes\/no\):/i.test(output)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Allow " + root.activeDeviceName + " to pair with this computer?";
        } else if (/Authorize service.*\(yes\/no\):/i.test(output)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Allow this Bluetooth service for " + root.activeDeviceName + "?";
        } else if (/Enter PIN code/i.test(output)) {
            root.pairingPromptType = "pin";
            root.pairingPromptText = "Enter the PIN requested by " + root.activeDeviceName + ".";
        } else if (/Enter passkey/i.test(output)) {
            root.pairingPromptType = "passkey";
            root.pairingPromptText = "Enter the passkey requested by " + root.activeDeviceName + ".";
        }

        if (root.actionStage === "pair" && /Pairing successful|Paired:\s*yes/i.test(output)) {
            root.pairingPromptType = "";
            root.actionStage = "connect";
            agentProcess.write("trust " + root.activeDeviceMac + "\nconnect " + root.activeDeviceMac + "\n");
        }
        if (root.actionStage === "connect" && /Connection successful/i.test(output)) {
            root.actionStage = "verify-connect";
            agentProcess.write("info " + root.activeDeviceMac + "\n");
        }
        if ((root.actionStage === "connect" || root.actionStage === "verify-connect") && /Connected:\s*yes/i.test(output)) {
            root.finishDeviceAction("Connected to " + root.activeDeviceName);
        } else if (root.actionStage === "disconnect" && /Successful disconnected/i.test(output)) {
            root.actionStage = "verify-disconnect";
            agentProcess.write("info " + root.activeDeviceMac + "\n");
        }
        if ((root.actionStage === "disconnect" || root.actionStage === "verify-disconnect") && /Connected:\s*no/i.test(output)) {
            root.finishDeviceAction("Disconnected from " + root.activeDeviceName);
        } else if (root.actionStage !== "" && /No agent available|Failed to pair|AuthenticationFailed|AuthenticationRejected|No route to host|page.?timeout|timed out|not available|NotReady/i.test(output)) {
            if (/No route|page.?timeout|timed out|not available|NotReady/i.test(output)) {
                root.finishDeviceAction("Device unreachable; wake it and bring it closer");
            } else if (/Authentication/i.test(output)) {
                root.finishDeviceAction("Pairing was rejected; keep the device in pairing mode and accept");
            } else {
                root.finishDeviceAction("Bluetooth pairing agent unavailable; reopen the drawer and retry");
            }
        }
    }

    function answerPairing(accept): void {
        if (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey") {
            if (accept && root.pairingInputText.length === 0) return;
            if (accept) agentProcess.write(root.pairingInputText + "\n");
            else agentProcess.running = false;
        } else {
            agentProcess.write(accept ? "yes\n" : "no\n");
        }
        if (!accept) {
            root.finishDeviceAction("Pairing declined");
        } else {
            root.pairingPromptType = "";
            root.pairingInputText = "";
        }
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
                                    paired: false,
                                    connected: false
                                });
                            }
                        }
                    }
                    root.devices = list;
                    root.statusMessage = list.length > 0 ? "" : (root.isScanning ? "Scanning for nearby devices..." : "No Bluetooth devices found");
                    pairedProcess.running = true;
                } catch (e) {
                    root.statusMessage = "Error reading devices";
                }
            }
        }
    }

    Process {
        id: pairedProcess
        command: ["bluetoothctl", "devices", "Paired"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var pairedMacs = {};
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (!line.startsWith("Device ")) continue;
                    var parts = line.split(" ");
                    if (parts.length >= 2) pairedMacs[parts[1].trim()] = true;
                }
                var updated = [];
                for (var j = 0; j < root.devices.length; j++) {
                    var d = root.devices[j];
                    updated.push({ mac: d.mac, name: d.name, paired: !!pairedMacs[d.mac], connected: false });
                }
                root.devices = updated;
                connectedProcess.running = true;
            }
        }
    }

    Process {
        id: connectedProcess
        command: ["bluetoothctl", "devices", "Connected"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lines = text.trim().split("\n");
                    var connectedMacs = {};
                    for (var i = 0; i < lines.length; i++) {
                        var line = lines[i].trim();
                        if (!line.startsWith("Device ")) continue;
                        var parts = line.split(" ");
                        if (parts.length >= 2) {
                            connectedMacs[parts[1].trim()] = true;
                        }
                    }
                    var updated = [];
                    for (var j = 0; j < root.devices.length; j++) {
                        var d = root.devices[j];
                        var connected = !!connectedMacs[d.mac];
                        if (!d.paired && !connected && !root.isScanning && !root.discoveredMacs[d.mac.toUpperCase()]) continue;
                        updated.push({
                            mac: d.mac,
                            name: d.name,
                            paired: d.paired,
                            connected: connected
                        });
                    }
                    root.devices = root.collapseAddressVariants(updated);
                } catch (e) {}
            }
        }
    }

    Process {
        id: scanProcess
        running: false
        onExited: (exitCode) => {
            root.isScanning = false;
            root.refresh();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var seen = {};
                var lines = text.split("\n");
                var addressPattern = /([0-9A-F]{2}:){5}[0-9A-F]{2}/i;
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (line.indexOf("RSSI:") < 0 && line.indexOf("NEW") < 0) continue;
                    var match = line.match(addressPattern);
                    if (match) seen[match[0].toUpperCase()] = true;
                }
                root.discoveredMacs = seen;
                root.isScanning = false;
                root.refresh();
            }
        }
    }

    Timer {
        id: devicePollingTimer
        interval: 3000
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    Process {
        id: agentProcess
        command: ["bash", "-c", "exec 2>&1; exec bluetoothctl --agent KeyboardDisplay"]
        running: false
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                root.agentOutputOffset = agentOutput.text.length;
                agentProcess.write("default-agent\n");
            } else {
                root.agentReady = false;
                if (root.isConnecting) root.finishDeviceAction("Bluetooth pairing agent stopped");
            }
        }
        stdout: StdioCollector {
            id: agentOutput
            waitForEnd: false
            onTextChanged: root.handleAgentOutput(text)
        }
    }

    Timer {
        id: actionTimeout
        interval: 45000
        repeat: false
        running: root.isConnecting
        onTriggered: {
            root.finishDeviceAction("Bluetooth request timed out");
            agentProcess.running = false;
        }
    }

    function connectDevice(dev): void {
        if (root.isConnecting) return;
        root.isConnecting = true;
        root.actionMessage = dev.connected ? "Disconnecting from " + dev.name + "..." : (dev.paired ? "Connecting to " : "Pairing with ") + dev.name + "...";
        root.activeDeviceMac = dev.mac;
        root.activeDeviceName = dev.name;
        root.activeDevicePaired = dev.paired;
        root.disconnecting = dev.connected;
        root.agentOutputOffset = agentOutput.text.length;
        root.pairingPromptType = "";
        root.pairingInputText = "";
        root.actionStage = root.agentReady ? "" : "waiting-agent";
        if (root.agentReady) root.beginDeviceAction();
        else root.ensureAgent();
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
                            text: devRow.modelData.connected ? "Connected" : (devRow.modelData.paired ? "Paired" : devRow.modelData.mac)
                            font.pixelSize: 9
                            color: devRow.modelData.connected ? Tokens.accent : Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        width: 58
                        height: 22
                        radius: 6
                        color: btnHover.hovered ? Tokens.accent : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                        border.color: Tokens.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.isConnecting && root.activeDeviceMac === devRow.modelData.mac ? "..." : (devRow.modelData.connected ? "Disconnect" : (devRow.modelData.paired ? "Connect" : "Pair"))
                            font.pixelSize: 9
                            font.bold: true
                            color: btnHover.hovered ? Tokens.surface : Tokens.accent
                        }

                        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !root.isConnecting; onTapped: root.connectDevice(devRow.modelData) }
                    }
                }
            }
        }

        // Status Message Footer
        Text {
            Layout.fillWidth: true
            visible: root.actionMessage.length > 0 || root.statusMessage.length > 0
            text: root.actionMessage.length > 0 ? root.actionMessage : root.statusMessage
            font.pixelSize: 10
            color: Tokens.accent
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.pairingPromptType.length > 0
        color: Qt.rgba(0, 0, 0, 0.62)
        z: 10

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 24
            height: root.pairingPromptType === "pin" || root.pairingPromptType === "passkey" ? 176 : 146
            radius: 14
            color: Tokens.surface_high
            border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.7)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Bluetooth pairing"
                    font.pixelSize: 13
                    font.bold: true
                    color: Tokens.text_primary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.pairingPromptText
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 7
                    visible: root.pairingPromptType === "pin" || root.pairingPromptType === "passkey"
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)
                    border.color: Tokens.outline

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 8
                        text: root.pairingInputText
                        color: Tokens.text_primary
                        font.pixelSize: 11
                        inputMethodHints: Qt.ImhDigitsOnly
                        onTextChanged: root.pairingInputText = text
                        onVisibleChanged: if (visible) forceActiveFocus()
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    Rectangle {
                        width: 76
                        height: 28
                        radius: 7
                        color: rejectHover.hovered ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.35) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.85)
                        border.color: Tokens.outline
                        Text { anchors.centerIn: parent; text: "Reject"; font.pixelSize: 10; color: Tokens.text_primary }
                        HoverHandler { id: rejectHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.answerPairing(false) }
                    }

                    Rectangle {
                        width: 76
                        height: 28
                        radius: 7
                        color: acceptHover.hovered ? Tokens.accent : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.8)
                        Text {
                            anchors.centerIn: parent
                            text: root.pairingPromptType === "pin" || root.pairingPromptType === "passkey" ? "Submit" : "Allow"
                            font.pixelSize: 10
                            font.bold: true
                            color: Tokens.surface
                        }
                        HoverHandler { id: acceptHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            enabled: (root.pairingPromptType !== "pin" && root.pairingPromptType !== "passkey") || root.pairingInputText.length > 0
                            onTapped: root.answerPairing(true)
                        }
                    }
                }
            }
        }
    }
}
