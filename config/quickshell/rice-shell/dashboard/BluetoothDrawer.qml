pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
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

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var devices: btAdapter && btAdapter.enabled ? visibleDevices(btAdapter.devices.values) : []
    readonly property bool isScanning: btAdapter ? btAdapter.discovering : false
    property var scanOwnedAdapter: null
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
    property string agentOutputTail: ""

    onBtAdapterChanged: {
        if (scanOwnedAdapter && scanOwnedAdapter !== btAdapter) stopScan();
        if (root.visible && btAdapter) root.startScan();
    }
    onIsScanningChanged: {
        if (!isScanning) {
            if (scanOwnedAdapter === btAdapter) {
                scanStopTimer.stop();
                scanOwnedAdapter = null;
            }
            if (statusMessage === "Scanning for devices...") statusMessage = "";
        }
    }

    onVisibleChanged: {
        if (visible) {
            actionMessage = "";
            startScan();
        } else {
            stopScan();
            finishDeviceAction("");
            agentReady = false;
            agentOutputTail = "";
            agentProcess.running = false;
        }
    }

    function visibleDevices(values) {
        var listed = [];
        for (var i = 0; i < values.length; i++) {
            var device = values[i];
            if (!device.address) continue;
            listed.push({
                mac: device.address,
                name: device.name || device.address,
                paired: device.paired,
                connected: device.connected
            });
        }
        return listed;
    }

    function startScan(): void {
        if (!btAdapter || !btAdapter.enabled) {
            statusMessage = "Bluetooth is off";
            return;
        }
        statusMessage = "Scanning for devices...";
        if (btAdapter.discovering) return;
        scanOwnedAdapter = btAdapter;
        btAdapter.discovering = true;
        scanStopTimer.restart();
    }

    function stopScan(): void {
        scanStopTimer.stop();
        var owned = scanOwnedAdapter;
        scanOwnedAdapter = null;
        if (owned && owned.discovering) owned.discovering = false;
    }

    function toggleScan(): void {
        if (isScanning) {
            stopScan();
        } else {
            startScan();
        }
    }

    function ensureAgent(): void {
        if (!agentProcess.running) agentProcess.running = true;
    }

    function isValidMac(mac): bool {
        return typeof mac === "string" && /^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$/.test(mac.trim());
    }

    function isEventForActiveDevice(match, output): bool {
        if (!root.activeDeviceMac) return true;
        var lineStart = output.lastIndexOf("\n", match.index);
        var lineEnd = output.indexOf("\n", match.index + match[0].length);
        var line = output.slice(lineStart === -1 ? 0 : lineStart + 1, lineEnd === -1 ? output.length : lineEnd);
        var devMatch = line.match(/Device\s+([0-9A-Fa-f:]{17})/i);
        if (devMatch) {
            return devMatch[1].toUpperCase() === root.activeDeviceMac.toUpperCase();
        }
        return true;
    }

    function beginDeviceAction(): void {
        if (!root.isConnecting || !root.agentReady) return;
        if (!root.isValidMac(root.activeDeviceMac)) {
            root.finishDeviceAction("Invalid device address");
            return;
        }
        if (root.disconnecting) {
            root.actionStage = "disconnect";
            agentProcess.write("disconnect " + root.activeDeviceMac + "\n");
        } else if (root.activeDevicePaired) {
            root.actionStage = "connect";
            agentProcess.write("connect " + root.activeDeviceMac + "\n");
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
    }

    function freshMatch(pattern, output, previousLength) {
        // A previous match in the overlap buffer must not be handled twice.
        var scanner = new RegExp(pattern.source, "gi");
        var match;
        while ((match = scanner.exec(output)) !== null) {
            if (match.index + match[0].length > previousLength) return match;
            if (match[0].length === 0) scanner.lastIndex++;
        }
        return null;
    }

    function handleAgentOutput(value): void {
        if (value.length < root.agentOutputOffset) {
            root.agentOutputOffset = 0;
            root.agentOutputTail = "";
        }
        var fresh = value.slice(root.agentOutputOffset);
        root.agentOutputOffset = value.length;
        if (fresh.length === 0) return;
        var previousLength = root.agentOutputTail.length;
        var output = (root.agentOutputTail + fresh).replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "\n");
        root.agentOutputTail = output.slice(-192);
        if (!root.isConnecting) return;

        if (root.freshMatch(/Default agent request successful/i, output, previousLength)) {
            root.agentReady = true;
            if (root.actionStage === "waiting-agent") root.beginDeviceAction();
        }

        var passkey = root.freshMatch(/Confirm passkey\s+(\d{6})/i, output, previousLength);
        if (passkey && root.isEventForActiveDevice(passkey, output)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Confirm that " + passkey[1] + " appears on both devices.";
        } else if (root.freshMatch(/Accept pairing\s*\(yes\/no\):/i, output, previousLength)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Allow " + root.activeDeviceName + " to pair with this computer?";
        } else if (root.freshMatch(/Authorize service.*\(yes\/no\):/i, output, previousLength)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Allow this Bluetooth service for " + root.activeDeviceName + "?";
        } else if (root.freshMatch(/Enter PIN code/i, output, previousLength)) {
            root.pairingPromptType = "pin";
            root.pairingPromptText = "Enter the PIN requested by " + root.activeDeviceName + ".";
        } else if (root.freshMatch(/Enter passkey/i, output, previousLength)) {
            root.pairingPromptType = "passkey";
            root.pairingPromptText = "Enter the passkey requested by " + root.activeDeviceName + ".";
        }

        var pairMatch = root.freshMatch(/Pairing successful|Paired:\s*yes/i, output, previousLength);
        if (root.actionStage === "pair" && pairMatch && root.isEventForActiveDevice(pairMatch, output)) {
            root.pairingPromptType = "";
            root.actionStage = "connect";
            agentProcess.write("trust " + root.activeDeviceMac + "\nconnect " + root.activeDeviceMac + "\n");
        }
        if (root.actionStage === "connect" && root.freshMatch(/Connection successful/i, output, previousLength)) {
            root.actionStage = "verify-connect";
            agentProcess.write("info " + root.activeDeviceMac + "\n");
        }
        var connMatch = root.freshMatch(/Connected:\s*yes/i, output, previousLength);
        if ((root.actionStage === "connect" || root.actionStage === "verify-connect") && connMatch && root.isEventForActiveDevice(connMatch, output)) {
            root.finishDeviceAction("Connected to " + root.activeDeviceName);
        } else if (root.actionStage === "disconnect") {
            var disconnectMatch = root.freshMatch(/Successful disconnected/i, output, previousLength);
            if (disconnectMatch && root.isEventForActiveDevice(disconnectMatch, output)) {
            root.actionStage = "verify-disconnect";
            agentProcess.write("info " + root.activeDeviceMac + "\n");
            }
        }
        var discMatch = root.freshMatch(/Connected:\s*no/i, output, previousLength);
        if ((root.actionStage === "disconnect" || root.actionStage === "verify-disconnect") && discMatch && root.isEventForActiveDevice(discMatch, output)) {
            root.finishDeviceAction("Disconnected from " + root.activeDeviceName);
        } else if (root.actionStage !== "" && root.freshMatch(/No agent available|Failed to pair|AuthenticationFailed|AuthenticationRejected|No route to host|page.?timeout|timed out|not available|NotReady/i, output, previousLength)) {
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
            if (accept) {
                var input = root.pairingInputText.trim();
                if (/[\r\n\x00-\x1f\x7f]/.test(input)) {
                    root.actionMessage = "Invalid characters in input";
                    return;
                }
                if (root.pairingPromptType === "passkey") {
                    if (!/^\d{6}$/.test(input)) {
                        root.actionMessage = "Passkey must be exactly 6 digits";
                        return;
                    }
                } else if (root.pairingPromptType === "pin") {
                    if (!/^[a-zA-Z0-9]{1,16}$/.test(input)) {
                        root.actionMessage = "PIN must be 1-16 alphanumeric characters";
                        return;
                    }
                }
                agentProcess.write(input + "\n");
            } else {
                agentProcess.running = false;
            }
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

    Timer {
        id: scanStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            root.stopScan();
        }
    }

    Process {
        id: agentProcess
        command: ["bash", "-c", "exec 2>&1; LC_ALL=C exec bluetoothctl --agent KeyboardDisplay"]
        running: false
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                root.agentOutputOffset = agentOutput.text.length;
                root.agentOutputTail = "";
                agentProcess.write("default-agent\n");
            } else {
                root.agentReady = false;
                root.agentOutputTail = "";
                if (root.isConnecting) root.finishDeviceAction("Bluetooth pairing agent stopped");
            }
        }
        stdout: StdioCollector {
            id: agentOutput
            waitForEnd: false
            onTextChanged: root.handleAgentOutput(text)
        }
    }

    Component.onDestruction: {
        stopScan();
        finishDeviceAction("");
        agentReady = false;
        agentProcess.running = false;
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
        if (!dev || !root.isValidMac(dev.mac)) {
            root.finishDeviceAction("Invalid Bluetooth device address");
            return;
        }
        root.isConnecting = true;
        root.actionMessage = dev.connected ? "Disconnecting from " + dev.name + "..." : (dev.paired ? "Connecting to " : "Pairing with ") + dev.name + "...";
        root.activeDeviceMac = dev.mac.trim();
        root.activeDeviceName = dev.name;
        root.activeDevicePaired = dev.paired;
        root.disconnecting = dev.connected;
        root.agentOutputOffset = agentOutput.text.length;
        root.agentOutputTail = "";
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
        if (root.visible) startScan();
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
