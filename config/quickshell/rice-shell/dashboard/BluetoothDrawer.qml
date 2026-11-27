pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"

Item {
    id: root
    property bool settingsPage: false
    property bool compactMenu: false

    anchors.fill: settingsPage || compactMenu ? undefined : parent
    implicitWidth: 360
    implicitHeight: settingsPage ? pageContent.implicitHeight
        : compactMenu ? Math.max(pageContent.implicitHeight, deviceDialog.visible ? dialogCard.height + 24 : 0)
        : 420
    clip: true
    focus: !settingsPage
    activeFocusOnTab: settingsPage
    Accessible.role: Accessible.Pane
    Accessible.name: "Bluetooth devices"
    objectName: "bluetoothDrawerPage"

    signal closeRequested()
    signal requestSettings(string route)

    // The adapter override is a deterministic seam for isolated tests.
    property var adapterOverride: null
    readonly property var btAdapter: root.adapterOverride || Bluetooth.defaultAdapter
    readonly property bool isPowered: !!root.btAdapter && root.btAdapter.enabled
    readonly property bool isAdapterTransitioning: !!root.btAdapter
        && (root.btAdapter.state === BluetoothAdapterState.Enabling
            || root.btAdapter.state === BluetoothAdapterState.Disabling)
    readonly property bool isAdapterBlocked: !!root.btAdapter
        && root.btAdapter.state === BluetoothAdapterState.Blocked
    readonly property bool powerTargetOn: root.pendingPowerTarget !== null
        ? !!root.pendingPowerTarget
        : (!!root.btAdapter && root.btAdapter.state === BluetoothAdapterState.Enabling)
    readonly property bool isScanning: !!root.btAdapter && root.btAdapter.discovering
    readonly property var devices: root.isPowered && root.btAdapter
        ? root.visibleDevices(root.btAdapter.devices.values) : []
    readonly property var deviceSections: root.classifyDevices(root.devices)

    property var scanOwnedAdapter: null
    property string statusMessage: ""
    property string actionMessage: ""
    property bool isConnecting: false
    property string activeDeviceMac: ""
    property string activeDeviceName: ""
    property var activeDeviceRef: null
    property var activeAdapterRef: null
    property string actionStage: ""
    property bool agentReady: false
    property string pairingPromptType: ""
    property string pairingPromptText: ""
    property string pairingInputText: ""
    property int agentOutputOffset: 0
    property string agentOutputTail: ""

    property bool isPowerPending: false
    property var pendingPowerTarget: null
    property bool forgetDialogOpen: false
    property bool isForgetPending: false
    property var pendingForgetDevice: null
    property string expandedDeviceKey: ""

    onBtAdapterChanged: {
        root.stopScan();
        if (root.actionStage === "pair") {
            root.cancelDeviceAction("Bluetooth adapter changed");
        } else if (root.isConnecting) {
            root.finishDeviceAction("");
        }
        if (root.isPowerPending) {
            powerTimeout.stop();
            root.isPowerPending = false;
            root.pendingPowerTarget = null;
        }
        if (root.visible && root.isPowered) Qt.callLater(root.startScan);
    }

    onIsPoweredChanged: {
        root.observeAdapterPower();
        if (!root.isPowered) {
            root.stopScan();
            if (root.actionStage === "pair") {
                root.cancelDeviceAction("Bluetooth was turned off");
            } else if (root.isConnecting) {
                root.finishDeviceAction("Bluetooth was turned off");
            }
        } else if (root.visible && !root.isPowerPending && !root.isAdapterTransitioning) {
            root.startScan();
        }
    }

    onIsAdapterTransitioningChanged: {
        var wasPending = root.isPowerPending;
        root.observeAdapterPower();
        if (!wasPending && !root.isAdapterTransitioning && root.isPowered && root.visible) {
            root.startScan();
        }
    }
    onIsAdapterBlockedChanged: root.observeAdapterPower()

    Connections {
        target: root.activeDeviceRef
        ignoreUnknownSignals: true
        function onConnectedChanged() { root.observeDeviceAction(); }
        function onPairedChanged() { root.observeForget(); }
    }

    Connections {
        target: root.pendingForgetDevice ? root.pendingForgetDevice.deviceRef : null
        ignoreUnknownSignals: true
        function onPairedChanged() { root.observeForget(); }
    }

    onIsScanningChanged: {
        if (!root.isScanning && root.scanOwnedAdapter === root.btAdapter) {
            scanStopTimer.stop();
            root.scanOwnedAdapter = null;
            if (root.statusMessage === "Scanning for Bluetooth devices…") root.statusMessage = "";
        }
    }

    onDevicesChanged: {
        root.observeDeviceAction();
        root.observeForget();
    }

    onVisibleChanged: {
        if (root.visible) {
            root.actionMessage = "";
            root.startScan();
        } else {
            root.stopScan();
            root.forgetDialogOpen = false;
            root.pendingForgetDevice = null;
            if (root.actionStage === "pair") {
                root.cancelDeviceAction("Pairing cancelled");
            } else if (root.isConnecting) {
                // Native connect/disconnect requests continue at BlueZ; only
                // their short-lived page state is discarded.
                root.finishDeviceAction("");
            }
            root.agentReady = false;
            root.agentOutputTail = "";
            agentProcess.running = false;
        }
    }

    function visibleDevices(values) {
        var listed = [];
        var source = values || [];
        for (var i = 0; i < source.length; i++) {
            var device = source[i];
            if (!device) continue;
            if (device.adapter && device.adapter !== root.btAdapter) continue;
            var address = String(device.address || "").trim().toUpperCase();
            var normalizedAddress = address.replace(/[:-]/g, "");
            var path = String(device.dbusPath || "");
            var key = normalizedAddress ? "address:" + normalizedAddress : path ? "path:" + path : "object:" + i;
            var existing = -1;
            for (var j = 0; j < listed.length; j++) {
                if (listed[j].identity === key || (!address && !path && listed[j].deviceRef === device)) {
                    existing = j;
                    break;
                }
            }
            var hasBattery = device.batteryAvailable === true;
            var batteryPercent = null;
            if (hasBattery && device.battery === device.battery) {
                batteryPercent = Math.max(0, Math.min(100, Math.round(device.battery * 100)));
            }
            var projected = {
                identity: key,
                key: path || address || key,
                mac: String(device.address || "").trim(),
                name: device.name || device.deviceName || device.address || "Bluetooth device",
                iconName: device.icon || "",
                paired: !!device.paired,
                connected: !!device.connected,
                trusted: !!device.trusted,
                blocked: !!device.blocked,
                batteryAvailable: hasBattery,
                batteryPercent: batteryPercent,
                deviceRef: device,
                adapterRef: device.adapter || root.btAdapter
            };
            if (existing < 0) {
                listed.push(projected);
            } else {
                var prior = listed[existing];
                projected.connected = prior.connected || projected.connected;
                projected.paired = prior.paired || projected.paired;
                projected.trusted = prior.trusted || projected.trusted;
                projected.blocked = prior.blocked || projected.blocked;
                if (prior.connected || (!projected.connected && prior.paired)) {
                    projected.deviceRef = prior.deviceRef;
                    projected.adapterRef = prior.adapterRef;
                }
                if (!projected.batteryAvailable && prior.batteryAvailable) {
                    projected.batteryAvailable = true;
                    projected.batteryPercent = prior.batteryPercent;
                }
                listed[existing] = projected;
            }
        }
        return listed;
    }

    function classifyDevices(values) {
        var sections = { connected: [], paired: [], available: [] };
        var source = values || [];
        for (var i = 0; i < source.length; i++) {
            var device = source[i];
            if (device.connected) sections.connected.push(device);
            else if (device.paired) sections.paired.push(device);
            else sections.available.push(device);
        }
        return sections;
    }

    function compactStatusText(): string {
        if (!root.btAdapter) return "Adapter unavailable";
        if (root.isAdapterBlocked) return "Blocked";
        if (root.isPowerPending || root.isAdapterTransitioning)
            return root.powerTargetOn ? "Turning on…" : "Turning off…";
        if (!root.isPowered) return "Off";
        if (root.isScanning) return "Scanning…";
        return String(root.deviceSections.connected.length) + " connected";
    }

    function compactEmptyStateVisible(): bool {
        return !root.btAdapter || (root.isPowered && root.devices.length === 0);
    }

    function isValidMac(mac): bool {
        if (typeof mac !== "string") return false;
        var value = mac.trim();
        if (value.length !== 17) return false;
        for (var i = 0; i < value.length; i++) {
            var code = value.charCodeAt(i);
            if (i === 2 || i === 5 || i === 8 || i === 11 || i === 14) {
                if (value.charAt(i) !== ":") return false;
            } else if (!((code >= 48 && code <= 57)
                         || (code >= 65 && code <= 70)
                         || (code >= 97 && code <= 102))) {
                return false;
            }
        }
        return true;
    }

    function isValidDeviceEntry(entry): bool {
        if (!entry || !root.isValidMac(entry.mac)) return false;
        if (entry.deviceRef && entry.adapterRef && root.btAdapter && entry.adapterRef !== root.btAdapter) return false;
        if (entry.deviceRef && entry.deviceRef.adapter && root.btAdapter && entry.deviceRef.adapter !== root.btAdapter) return false;
        if (entry.deviceRef && entry.deviceRef.address && String(entry.deviceRef.address).toUpperCase() !== entry.mac.toUpperCase()) return false;
        return true;
    }

    function macFromContextLine(line): string {
        var lower = line.toLowerCase();
        var markers = [
            "device ",
            "attempting to pair with ",
            "attempting to connect to ",
            "attempting to disconnect from "
        ];
        var markerIndex = -1;
        var markerLength = 0;
        for (var i = 0; i < markers.length; i++) {
            var candidateIndex = lower.lastIndexOf(markers[i]);
            if (candidateIndex > markerIndex) {
                markerIndex = candidateIndex;
                markerLength = markers[i].length;
            }
        }
        if (markerIndex < 0) return "";
        var mac = line.slice(markerIndex + markerLength, markerIndex + markerLength + 17).trim();
        return root.isValidMac(mac) ? mac.toUpperCase() : "";
    }

    function isEventForActiveDevice(match, output): bool {
        if (!match) return false;
        if (!root.activeDeviceMac) return true;
        var cursor = match.index + match[0].length;
        while (cursor >= 0) {
            var lineStart = output.lastIndexOf("\n", Math.max(0, cursor - 1)) + 1;
            var line = output.slice(lineStart, cursor);
            var eventMac = root.macFromContextLine(line);
            if (eventMac) return eventMac === root.activeDeviceMac.toUpperCase();
            if (lineStart === 0) break;
            cursor = lineStart - 1;
        }
        return false;
    }

    function validatePairingInput(type, value): bool {
        if (typeof value !== "string" || value.length === 0) return false;
        if (type === "passkey") {
            if (value.length > 6) return false;
            for (var i = 0; i < value.length; i++) {
                var digit = value.charCodeAt(i);
                if (digit < 48 || digit > 57) return false;
            }
            return true;
        }
        if (type !== "pin" || value.length > 16) return false;
        for (var j = 0; j < value.length; j++) {
            var character = value.charCodeAt(j);
            // bluetoothctl consumes PINs as one line; accept printable ASCII
            // and reject control characters, line breaks, and delimiters.
            if (character < 32 || character > 126) return false;
        }
        return true;
    }

    function startScan(): void {
        root.actionMessage = "";
        if (!root.btAdapter) {
            root.statusMessage = "Bluetooth adapter unavailable";
            return;
        }
        if (root.isAdapterBlocked) {
            root.statusMessage = "Bluetooth is blocked by the system";
            return;
        }
        if (root.isAdapterTransitioning) {
            root.statusMessage = "Bluetooth power is changing";
            return;
        }
        if (!root.isPowered) {
            root.statusMessage = "Bluetooth is off";
            return;
        }
        if (root.btAdapter.discovering) {
            root.statusMessage = root.scanOwnedAdapter === root.btAdapter
                ? "Scanning for Bluetooth devices…" : "Bluetooth scan is already active";
            return;
        }
        root.statusMessage = "Scanning for Bluetooth devices…";
        root.scanOwnedAdapter = root.btAdapter;
        root.btAdapter.discovering = true;
        scanStopTimer.restart();
    }

    function stopScan(): void {
        scanStopTimer.stop();
        var owned = root.scanOwnedAdapter;
        root.scanOwnedAdapter = null;
        if (owned && owned.discovering) owned.discovering = false;
    }

    function toggleScan(): void {
        if (!root.btAdapter || !root.isPowered || root.isAdapterBlocked || root.isAdapterTransitioning
                || root.isPowerPending || root.isConnecting) return;
        if (root.scanOwnedAdapter === root.btAdapter && root.isScanning) {
            root.stopScan();
            return;
        }
        if (root.isScanning) {
            root.statusMessage = "Bluetooth scan is already active";
            return;
        }
        root.startScan();
    }

    function requestAdapterPower(enabled): bool {
        root.actionMessage = "";
        if (!root.btAdapter) {
            root.statusMessage = "Bluetooth adapter unavailable";
            return false;
        }
        if (root.isAdapterBlocked && enabled) {
            root.statusMessage = "Bluetooth is blocked by the system";
            return false;
        }
        if (root.isAdapterTransitioning) {
            root.statusMessage = "Bluetooth power is already changing";
            return false;
        }
        if (root.isPowerPending || root.isConnecting || root.isForgetPending) {
            root.statusMessage = "Finish the current Bluetooth request first";
            return false;
        }
        if (!!root.btAdapter.enabled === !!enabled) return false;

        root.isPowerPending = true;
        root.pendingPowerTarget = !!enabled;
        root.statusMessage = enabled ? "Turning Bluetooth on…" : "Turning Bluetooth off…";
        if (!enabled) root.stopScan();
        try {
            root.btAdapter.enabled = !!enabled;
        } catch (error) {
            powerTimeout.stop();
            root.isPowerPending = false;
            root.pendingPowerTarget = null;
            root.statusMessage = "Could not change Bluetooth power";
            return false;
        }
        root.observeAdapterPower();
        if (root.isPowerPending) powerTimeout.restart();
        return true;
    }

    function observeAdapterPower(): void {
        if (!root.isPowerPending) return;
        if (!root.btAdapter) {
            powerTimeout.stop();
            root.isPowerPending = false;
            root.pendingPowerTarget = null;
            root.statusMessage = "Bluetooth adapter unavailable";
            return;
        }
        if (root.isAdapterTransitioning) return;
        if (root.isAdapterBlocked && root.pendingPowerTarget) {
            powerTimeout.stop();
            root.isPowerPending = false;
            root.pendingPowerTarget = null;
            root.statusMessage = "Bluetooth is blocked by the system";
            return;
        }
        if (!!root.btAdapter.enabled !== root.pendingPowerTarget) return;
        var enabled = root.pendingPowerTarget;
        powerTimeout.stop();
        root.isPowerPending = false;
        root.pendingPowerTarget = null;
        root.statusMessage = enabled ? "Bluetooth is on" : "Bluetooth is off";
        if (enabled && root.visible) root.startScan();
    }

    function observeDeviceAction(): void {
        if (!root.isConnecting) return;
        if (!root.btAdapter || root.activeAdapterRef !== root.btAdapter) {
            if (root.actionStage === "pair") root.cancelDeviceAction("Bluetooth adapter changed");
            else root.finishDeviceAction("Bluetooth adapter changed");
            return;
        }
        var stillPresent = false;
        for (var i = 0; i < root.devices.length; i++) {
            if (root.devices[i].deviceRef === root.activeDeviceRef) {
                stillPresent = true;
                break;
            }
        }
        if (!stillPresent) {
            if (root.actionStage === "pair") root.cancelDeviceAction("Bluetooth device disappeared");
            else root.finishDeviceAction("Bluetooth device disappeared");
        } else if (root.actionStage === "connect" && root.activeDeviceRef.connected) {
            root.finishDeviceAction("Connected to " + root.activeDeviceName);
        } else if (root.actionStage === "disconnect" && !root.activeDeviceRef.connected) {
            root.finishDeviceAction("Disconnected from " + root.activeDeviceName);
        }
    }

    function connectDevice(entry): void {
        if (root.isConnecting || root.isPowerPending || root.isForgetPending) return;
        root.statusMessage = "";
        if (!root.isValidDeviceEntry(entry)) {
            root.actionMessage = "Bluetooth device is no longer available";
            return;
        }
        if (entry.blocked) {
            root.actionMessage = "This Bluetooth device is blocked";
            return;
        }

        root.activeDeviceRef = entry.deviceRef || null;
        root.activeAdapterRef = entry.adapterRef || null;
        root.activeDeviceMac = entry.mac.trim();
        root.activeDeviceName = entry.name || entry.mac;
        root.isConnecting = true;

        if (entry.connected) {
            root.actionStage = "disconnect";
            root.actionMessage = "Disconnecting from " + entry.name + "…";
            if (entry.deviceRef && typeof entry.deviceRef.disconnect === "function") {
                try {
                    entry.deviceRef.disconnect();
                } catch (error) {
                    root.finishDeviceAction("Could not disconnect from " + entry.name);
                    return;
                }
            }
        } else if (entry.paired) {
            root.actionStage = "connect";
            root.actionMessage = "Connecting to " + entry.name + "…";
            if (entry.deviceRef && typeof entry.deviceRef.connect === "function") {
                try {
                    entry.deviceRef.connect();
                } catch (error) {
                    root.finishDeviceAction("Could not connect to " + entry.name);
                    return;
                }
            }
        } else {
            root.actionStage = "waiting-agent";
            root.actionMessage = "Pairing with " + entry.name + "…";
            root.agentOutputOffset = agentOutput.text.length;
            root.agentOutputTail = "";
            root.pairingPromptType = "";
            root.pairingInputText = "";
            if (root.agentReady) root.beginDeviceAction();
            else root.ensureAgent();
        }

        if (root.isConnecting) actionTimeout.restart();
    }

    function ensureAgent(): void {
        if (!agentProcess.running) agentProcess.running = true;
    }

    function beginDeviceAction(): void {
        if (!root.isConnecting || !root.agentReady || root.actionStage !== "waiting-agent") return;
        if (!root.isValidMac(root.activeDeviceMac)) {
            root.finishDeviceAction("Invalid Bluetooth device address");
            return;
        }
        root.actionStage = "pair";
        agentProcess.write("pair " + root.activeDeviceMac + "\n");
    }

    function finishDeviceAction(message): void {
        actionTimeout.stop();
        root.isConnecting = false;
        root.activeDeviceMac = "";
        root.activeDeviceName = "";
        root.activeDeviceRef = null;
        root.activeAdapterRef = null;
        root.actionStage = "";
        root.pairingPromptType = "";
        root.pairingPromptText = "";
        root.pairingInputText = "";
        root.actionMessage = message;
    }

    function cancelDeviceAction(message): void {
        if (root.actionStage === "pair" || root.actionStage === "waiting-agent") {
            if (root.activeDeviceRef && root.activeDeviceRef.pairing) {
                root.activeDeviceRef.cancelPair();
            }
            if (agentProcess.running) agentProcess.running = false;
        }
        root.finishDeviceAction(message);
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
        var output = (root.agentOutputTail + fresh)
            .replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "")
            .replace(/\r/g, "\n");
        root.agentOutputTail = output.slice(-1024);
        if (!root.isConnecting) return;

        if (root.freshMatch(/Default agent request successful/i, output, previousLength)) {
            root.agentReady = true;
            if (root.actionStage === "waiting-agent") root.beginDeviceAction();
        }

        var passkey = root.freshMatch(/Confirm passkey\s+(\d{6})/i, output, previousLength);
        if (passkey && root.isEventForActiveDevice(passkey, output)) {
            root.pairingPromptType = "confirm";
            root.pairingPromptText = "Does " + root.activeDeviceName + " display code " + passkey[1] + "? Confirm only if the codes match.";
        } else {
            var pairing = root.freshMatch(/Accept pairing\s*\(yes\/no\):/i, output, previousLength);
            var service = root.freshMatch(/Authorize service.*\(yes\/no\):/i, output, previousLength);
            var pin = root.freshMatch(/Enter PIN code/i, output, previousLength);
            var passkeyInput = root.freshMatch(/Enter passkey/i, output, previousLength);
            if (pairing && root.isEventForActiveDevice(pairing, output)) {
                root.pairingPromptType = "confirm";
                root.pairingPromptText = "Allow " + root.activeDeviceName + " to pair with this computer?";
            } else if (service && root.isEventForActiveDevice(service, output)) {
                root.pairingPromptType = "confirm";
                root.pairingPromptText = "Allow this Bluetooth service for " + root.activeDeviceName + "?";
            } else if (pin && root.isEventForActiveDevice(pin, output)) {
                root.pairingPromptType = "pin";
                root.pairingPromptText = "Enter the PIN requested by " + root.activeDeviceName + ".";
            } else if (passkeyInput && root.isEventForActiveDevice(passkeyInput, output)) {
                root.pairingPromptType = "passkey";
                root.pairingPromptText = "Enter the passkey requested by " + root.activeDeviceName + ".";
            }
        }

        var paired = root.freshMatch(/Pairing successful|Paired:\s*yes/i, output, previousLength);
        if (root.actionStage === "pair" && paired && root.isEventForActiveDevice(paired, output)) {
            var pairedName = root.activeDeviceName;
            root.finishDeviceAction("Paired with " + pairedName);
            agentProcess.running = false;
            return;
        }

        var connMatch = root.freshMatch(/Connected:\s*yes/i, output, previousLength);
        if ((root.actionStage === "connect" || root.actionStage === "verify-connect") && connMatch && root.isEventForActiveDevice(connMatch, output)) {
            var connectedName = root.activeDeviceName;
            root.finishDeviceAction("Connected to " + connectedName);
            return;
        }

        var failed = root.freshMatch(/Failed to pair|AuthenticationFailed|AuthenticationRejected|No route to host|page.?timeout|timed out|not available|NotReady|No agent available/i, output, previousLength);
        if (root.actionStage === "pair" && failed && root.isEventForActiveDevice(failed, output)) {
            var failure = /Authentication/i.test(failed[0])
                ? "Pairing was rejected; accept the request on the device and retry"
                : /No route|page.?timeout|timed out|not available|NotReady/i.test(failed[0])
                    ? "Device unreachable; wake it and bring it closer"
                    : "Bluetooth pairing failed";
            root.cancelDeviceAction(failure);
        }
    }

    function answerPairing(accept): void {
        if (!root.pairingPromptType.length || !root.isConnecting) return;
        if (accept && (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey")) {
            var input = root.pairingInputText.trim();
            if (!root.validatePairingInput(root.pairingPromptType, input)) {
                root.actionMessage = "";
                root.statusMessage = root.pairingPromptType === "passkey"
                    ? "Enter a passkey of up to 6 digits"
                    : "PIN must be 1–16 printable characters";
                return;
            }
            agentProcess.write(input + "\n");
        } else if (root.pairingPromptType === "confirm") {
            agentProcess.write(accept ? "yes\n" : "no\n");
        }

        if (!accept) {
            root.cancelDeviceAction("Pairing declined");
        } else {
            root.pairingPromptType = "";
            root.pairingPromptText = "";
            root.pairingInputText = "";
            root.statusMessage = "";
        }
    }

    function requestForget(entry): bool {
        if (root.isConnecting || root.isPowerPending || root.isForgetPending) return false;
        root.actionMessage = "";
        if (!root.isValidDeviceEntry(entry) || !entry.paired || entry.connected) {
            root.statusMessage = "Disconnect the device before forgetting it";
            return false;
        }
        root.pendingForgetDevice = entry;
        root.forgetDialogOpen = true;
        return true;
    }

    function confirmForget(): bool {
        var entry = root.pendingForgetDevice;
        if (!root.forgetDialogOpen || !root.isValidDeviceEntry(entry)
                || !entry.deviceRef.paired || entry.deviceRef.connected) {
            root.statusMessage = "Bluetooth device is no longer available";
            root.cancelForget();
            return false;
        }
        root.forgetDialogOpen = false;
        root.isForgetPending = true;
        root.actionMessage = "";
        root.statusMessage = "Forgetting " + entry.name + "…";
        forgetTimeout.restart();
        try {
            entry.deviceRef.forget();
        } catch (error) {
            root.finishForget("Could not forget " + entry.name);
            return false;
        }
        root.observeForget();
        return true;
    }

    function cancelForget(): void {
        root.forgetDialogOpen = false;
        root.pendingForgetDevice = null;
    }

    function observeForget(): void {
        if (!root.isForgetPending || !root.pendingForgetDevice) return;
        if (!root.pendingForgetDevice.deviceRef.paired) {
            root.finishForget("Forgot " + root.pendingForgetDevice.name);
        }
    }

    function finishForget(message): void {
        forgetTimeout.stop();
        root.isForgetPending = false;
        root.pendingForgetDevice = null;
        root.actionMessage = "";
        root.statusMessage = message;
    }

    function handleEscape(): void {
        if (root.forgetDialogOpen) {
            root.cancelForget();
            return;
        }
        if (root.pairingPromptType.length) {
            root.answerPairing(false);
            return;
        }
        if (root.expandedDeviceKey.length) {
            root.expandedDeviceKey = "";
            return;
        }
        if (root.actionStage === "pair") {
            root.cancelDeviceAction("Pairing cancelled");
            return;
        }
        if (root.isConnecting) root.finishDeviceAction("");
        root.closeRequested();
    }

    function getDeviceIcon(name, iconName): string {
        var lower = String(name || "").toLowerCase();
        var icon = String(iconName || "").toLowerCase();
        if (lower.indexOf("tv") >= 0 || lower.indexOf("television") >= 0 || lower.indexOf("monitor") >= 0
                || lower.indexOf("display") >= 0 || lower.indexOf("webos") >= 0
                || icon.indexOf("video") >= 0 || icon.indexOf("display") >= 0 || icon.indexOf("tv") >= 0) return "󰔂";
        if (lower.indexOf("head") >= 0 || lower.indexOf("bud") >= 0 || lower.indexOf("airpod") >= 0 || lower.indexOf("wh-") >= 0) return "󰋋";
        if (lower.indexOf("speaker") >= 0 || lower.indexOf("sound") >= 0) return "󰓃";
        if (lower.indexOf("keyboard") >= 0 || lower.indexOf("key") >= 0) return "󰌌";
        if (lower.indexOf("mouse") >= 0 || lower.indexOf("mx") >= 0) return "󰍽";
        if (lower.indexOf("phone") >= 0 || lower.indexOf("galaxy") >= 0 || lower.indexOf("pixel") >= 0) return "󰏲";
        return "󰂯";
    }

    function deviceStatus(device): string {
        var state = device.connected ? "Connected" : (device.paired ? "Paired" : "Available");
        if (device.blocked) state += " · Blocked";
        if (device.connected && device.batteryAvailable && device.batteryPercent !== null) {
            state += " · " + device.batteryPercent + "% battery";
        }
        return state;
    }

    function isErrorMessage(message): bool {
        var lower = String(message || "").toLowerCase();
        return lower.indexOf("could not") >= 0 || lower.indexOf("failed") >= 0
            || lower.indexOf("timed out") >= 0 || lower.indexOf("unavailable") >= 0
            || lower.indexOf("rejected") >= 0 || lower.indexOf("blocked") >= 0;
    }

    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: function(event) {
        root.handleEscape();
        event.accepted = true;
    }

    Timer {
        id: scanStopTimer
        interval: 8000
        repeat: false
        onTriggered: root.stopScan()
    }

    Timer {
        id: powerTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            if (!root.isPowerPending) return;
            root.isPowerPending = false;
            root.pendingPowerTarget = null;
            root.statusMessage = "Bluetooth power change timed out";
        }
    }

    Timer {
        id: actionTimeout
        interval: 45000
        repeat: false
        onTriggered: {
            if (root.actionStage === "pair" || root.actionStage === "waiting-agent") {
                root.cancelDeviceAction("Bluetooth pairing timed out");
            } else {
                root.finishDeviceAction("Bluetooth device request timed out");
            }
        }
    }

    Timer {
        id: forgetTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.isForgetPending) root.finishForget("Bluetooth did not confirm the removal");
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
                if (root.isConnecting && (root.actionStage === "pair" || root.actionStage === "waiting-agent")) {
                    root.finishDeviceAction("Bluetooth pairing agent stopped");
                }
            }
        }
        stdout: StdioCollector {
            id: agentOutput
            waitForEnd: false
            onTextChanged: root.handleAgentOutput(text)
        }
    }

    Component.onCompleted: {
        if (root.visible) root.startScan();
    }

    Component.onDestruction: {
        root.stopScan();
        if (root.actionStage === "pair" || root.actionStage === "waiting-agent") {
            root.cancelDeviceAction("");
        } else {
            root.finishDeviceAction("");
        }
        agentProcess.running = false;
    }

    component ActionButton: Rectangle {
        id: actionButton
        objectName: root.compactMenu && isSwitch ? "bluetoothPowerSwitch" : ""

        property string text: ""
        property string accessibleLabel: text
        property bool actionable: true
        property bool emphasized: false
        property bool danger: false
        property bool isSwitch: false
        property bool checked: false
        signal activated()

        enabled: actionable
        activeFocusOnTab: true
        readonly property bool showAsSwitch: (root.settingsPage || root.compactMenu) && isSwitch
        implicitWidth: showAsSwitch ? (root.compactMenu ? 38 : 44) : Math.max(64, actionText.implicitWidth + 24)
        implicitHeight: showAsSwitch ? (root.compactMenu ? 22 : 24) : 34
        radius: root.settingsPage && !showAsSwitch ? 8 : height / 2
        color: showAsSwitch ? (root.compactMenu
            ? (checked ? Tokens.menuSwitch : Tokens.menuSurface)
            : (checked ? Tokens.accent : Tokens.surface_high))
            : root.settingsPage && !danger ? (buttonHover.hovered ? Tokens.surface_high : Tokens.surface)
            : !actionButton.actionable
            ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.35)
            : actionButton.danger
                ? (buttonHover.hovered ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.22) : Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.1))
                : actionButton.checked
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                    : actionButton.emphasized
                        ? (buttonHover.hovered ? Tokens.accent : Qt.darker(Tokens.accent, 1.08))
                        : (buttonHover.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.9) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.58))
        border.color: actionButton.activeFocus
            ? Tokens.accent
            : actionButton.danger
                ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.65)
                : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.45)
        border.width: actionButton.activeFocus || (!showAsSwitch && actionButton.checked) ? 2 : 1

        Accessible.role: actionButton.isSwitch ? Accessible.Switch : Accessible.Button
        Accessible.name: actionButton.accessibleLabel
        Accessible.description: actionButton.accessibleLabel
        Accessible.focusable: actionButton.actionable
        Accessible.checkable: actionButton.isSwitch
        Accessible.checked: actionButton.checked
        Accessible.onPressAction: if (actionButton.actionable) actionButton.activated()
        Accessible.onToggleAction: if (actionButton.actionable) actionButton.activated()

        HoverHandler {
            id: buttonHover
            enabled: actionButton.actionable
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: actionButton.actionable
            onTapped: {
                actionButton.forceActiveFocus();
                actionButton.activated();
            }
        }

        Keys.onReturnPressed: function(event) {
            if (actionButton.actionable) actionButton.activated();
            event.accepted = true;
        }
        Keys.onSpacePressed: function(event) {
            if (actionButton.actionable) actionButton.activated();
            event.accepted = true;
        }

        Rectangle {
            visible: actionButton.showAsSwitch
            objectName: root.compactMenu ? "bluetoothPowerSwitchThumb" : ""
            width: root.compactMenu ? 16 : 18
            height: width
            x: actionButton.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            color: actionButton.checked ? Tokens.on_accent
                : root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary
            Behavior on x { NumberAnimation { duration: root.compactMenu ? 160 : 0; easing.type: Easing.OutCubic } }
        }

        Text {
            id: actionText
            visible: !actionButton.showAsSwitch
            anchors.centerIn: parent
            text: actionButton.text
            font.pixelSize: root.settingsPage ? 13 : 11
            font.weight: Font.Medium
            color: !actionButton.actionable
                ? Tokens.text_secondary
                : root.settingsPage && !actionButton.danger ? Tokens.text_primary
                : actionButton.danger
                    ? Tokens.danger
                    : actionButton.emphasized
                        ? Tokens.surface
                        : actionButton.checked
                            ? Tokens.accent
                            : Tokens.text_primary
        }
    }

    ColumnLayout {
        id: pageContent
        anchors.fill: parent
        spacing: root.settingsPage ? 17 : (root.compactMenu ? 6 : 8)

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.settingsPage ? Math.max(68, radioControls.implicitHeight + 20)
                : root.compactMenu ? Math.max(50, radioControls.implicitHeight + 12) : Math.max(0, radioControls.implicitHeight)
            radius: root.compactMenu ? 11 : 10
            color: root.compactMenu ? Qt.tint(Tokens.menuSurface, Qt.alpha(Tokens.menuAccent, 0.06))
                : root.settingsPage ? Tokens.surface_low : "transparent"
            border.width: root.settingsPage ? 1 : 0
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)

            RowLayout {
                id: radioControls
                anchors.fill: parent
                anchors.leftMargin: root.settingsPage ? 14 : root.compactMenu ? 8 : 0
                anchors.rightMargin: anchors.leftMargin
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    visible: root.compactMenu
                    radius: 9
                    color: root.isPowered ? Tokens.menuSelected : Tokens.menuSurface
                    Accessible.ignored: true

                    Text {
                        anchors.centerIn: parent
                        text: root.isPowered ? "󰂯" : "󰂲"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17
                        color: root.isPowered ? Tokens.menuAccent : Tokens.menuMuted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 3

                    Text {
                        visible: root.settingsPage || root.compactMenu
                        text: root.compactMenu ? qsTr("Bluetooth") : qsTr("Bluetooth radio")
                        font.pixelSize: root.compactMenu ? 15 : 15
                        font.weight: Font.DemiBold
                        color: root.compactMenu ? Tokens.menuText : Tokens.text_primary
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.compactMenu
                        text: !root.btAdapter ? "Adapter unavailable"
                            : root.isAdapterBlocked ? "Bluetooth is blocked"
                            : root.isPowerPending || root.isAdapterTransitioning
                                ? (root.powerTargetOn ? "Turning on…" : "Turning off…")
                                : root.btAdapter.name
                                    ? root.btAdapter.name + " · " + (root.isPowered ? "On" : "Off")
                                    : (root.isPowered ? "Bluetooth is on" : "Bluetooth is off")
                        font.pixelSize: root.settingsPage ? 13 : 12
                        color: root.isAdapterBlocked ? Tokens.danger
                            : !root.settingsPage && root.isPowered ? Tokens.accent : Tokens.text_secondary
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.compactMenu
                        text: root.compactStatusText()
                        font.pixelSize: 12
                        color: Tokens.menuMuted
                        elide: Text.ElideRight
                    }
                }

                ActionButton {
                    text: root.isPowerPending
                        || root.isAdapterTransitioning
                        ? (root.powerTargetOn ? "Turning on" : "Turning off")
                        : (root.isPowered ? "Turn off" : "Turn on")
                    accessibleLabel: root.isPowerPending
                        || root.isAdapterTransitioning
                        ? (root.powerTargetOn ? "Bluetooth is turning on" : "Bluetooth is turning off")
                        : (root.isPowered ? "Turn Bluetooth off" : "Turn Bluetooth on")
                    isSwitch: true
                    checked: root.isPowered
                    emphasized: !root.settingsPage && !root.isPowered && !root.isPowerPending
                    actionable: !!root.btAdapter && !root.isAdapterBlocked && !root.isPowerPending
                        && !root.isAdapterTransitioning && !root.isConnecting && !root.isForgetPending
                    onActivated: root.requestAdapterPower(!root.isPowered)
                }

                ActionButton {
                    visible: !root.compactMenu && (!root.settingsPage || root.isPowered)
                    text: root.isScanning && root.scanOwnedAdapter === root.btAdapter ? qsTr("Stop scan")
                    : root.settingsPage ? qsTr("Scan devices") : "Scan"
                    accessibleLabel: root.isScanning && root.scanOwnedAdapter === root.btAdapter
                        ? "Stop Bluetooth scan" : (root.isScanning ? "Bluetooth scan already active" : "Scan for Bluetooth devices")
                    actionable: !!root.btAdapter && root.isPowered && !root.isPowerPending && !root.isConnecting && !root.isForgetPending
                    onActivated: root.toggleScan()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.compactMenu && root.isPowered
            implicitHeight: 1
            color: Tokens.menuLine
        }

        Item {
            id: pageBody
            Layout.fillWidth: true
            Layout.fillHeight: !root.compactMenu || root.isPowered
            Layout.minimumHeight: 0
            Layout.maximumHeight: root.compactMenu ? 300 : Number.POSITIVE_INFINITY
            implicitHeight: root.compactMenu
                ? Math.min(300, deviceList.visible ? deviceList.contentHeight
                    : root.isPowered && root.compactEmptyStateVisible() ? bluetoothEmpty.implicitHeight + 16 : 0)
                : root.settingsPage ? (deviceList.visible ? deviceList.contentHeight : bluetoothEmpty.implicitHeight + 46) : 280

            Flickable {
                id: deviceList
                anchors.fill: parent
                clip: true
                visible: root.isPowered && root.devices.length > 0
                contentWidth: width
                interactive: !root.settingsPage
                contentHeight: deviceContent.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: root.settingsPage ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

                ColumnLayout {
                    id: deviceContent
                    x: 0
                    width: deviceList.width
                    spacing: root.compactMenu ? 8 : root.settingsPage ? 18 : 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.compactMenu ? 2 : 7
                        visible: root.compactMenu ? root.deviceSections.connected.length > 0
                            : !root.settingsPage && root.devices.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.compactMenu ? 8 : 0
                            Text {
                                text: root.compactMenu ? qsTr("Connected") : "CONNECTED"
                                font.pixelSize: root.compactMenu ? 12 : 10
                                font.weight: Font.DemiBold
                                color: root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: !root.compactMenu
                                text: String(root.deviceSections.connected.length)
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Repeater {
                            model: root.settingsPage ? [] : root.deviceSections.connected
                            delegate: deviceCard
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMenu && root.deviceSections.connected.length === 0
                            text: "No connected devices"
                            font.pixelSize: root.settingsPage ? 13 : 11
                            color: Tokens.text_secondary
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
                        visible: !root.settingsPage && !root.compactMenu && root.devices.length > 0
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.compactMenu ? 2 : 7
                        visible: root.compactMenu ? root.deviceSections.paired.length > 0 : root.devices.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.compactMenu ? 8 : 0
                            Text {
                                text: root.compactMenu ? qsTr("My Devices")
                                    : root.settingsPage ? qsTr("Saved devices") : "PAIRED"
                                font.pixelSize: root.compactMenu ? 12 : root.settingsPage ? 15 : 10
                                font.weight: Font.DemiBold
                                color: root.compactMenu ? Tokens.menuMuted
                                    : root.settingsPage ? Tokens.text_primary : Tokens.text_secondary
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: !root.settingsPage && !root.compactMenu
                                text: String(root.deviceSections.paired.length)
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Repeater {
                            model: root.settingsPage ? root.deviceSections.connected.concat(root.deviceSections.paired)
                                : root.deviceSections.paired
                            delegate: deviceCard
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMenu && root.deviceSections.paired.length === 0
                                && (!root.settingsPage || root.deviceSections.connected.length === 0)
                            text: "No saved devices"
                            font.pixelSize: root.settingsPage ? 13 : 11
                            color: Tokens.text_secondary
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.28)
                        visible: !root.settingsPage && !root.compactMenu && root.devices.length > 0
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.compactMenu ? 2 : 7
                        visible: root.compactMenu ? root.deviceSections.available.length > 0 : root.devices.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.compactMenu ? 8 : 0
                            Text {
                                text: root.compactMenu ? qsTr("Nearby Devices")
                                    : root.settingsPage ? qsTr("Nearby devices") : "AVAILABLE"
                                font.pixelSize: root.compactMenu ? 12 : root.settingsPage ? 15 : 10
                                font.weight: Font.DemiBold
                                color: root.compactMenu ? Tokens.menuMuted
                                    : root.settingsPage ? Tokens.text_primary : Tokens.text_secondary
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: !root.settingsPage && !root.compactMenu
                                text: String(root.deviceSections.available.length)
                                font.pixelSize: 10
                                color: Tokens.text_secondary
                            }
                        }

                        Repeater {
                            model: root.deviceSections.available
                            delegate: deviceCard
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMenu && root.deviceSections.available.length === 0
                            text: root.isScanning ? "Looking for nearby devices…" : "No new devices found"
                            font.pixelSize: root.settingsPage ? 13 : 11
                            color: Tokens.text_secondary
                        }
                    }
                }
            }

            ColumnLayout {
                id: bluetoothEmpty
                anchors.centerIn: parent
                width: Math.min(parent.width - 24, 300)
                spacing: 10
                visible: root.compactMenu ? root.compactEmptyStateVisible()
                    : !root.btAdapter || !root.isPowered || root.devices.length === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.settingsPage && !root.compactMenu
                    text: "󰂯"
                    font.pixelSize: 30
                    color: Tokens.accent
                    Accessible.ignored: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.compactMenu ? root.btAdapter && root.isPowered && root.devices.length === 0
                        : !root.settingsPage || root.isPowered
                    text: root.compactMenu ? qsTr("Put a device in pairing mode to find it here.")
                        : !root.btAdapter ? "Bluetooth adapter unavailable"
                        : root.isAdapterBlocked ? "Bluetooth is blocked by the system"
                        : !root.isPowered ? "Bluetooth is off"
                        : root.isScanning ? "Scanning for devices…"
                        : "No Bluetooth devices found"
                    font.pixelSize: root.compactMenu ? 12 : 14
                    font.weight: root.compactMenu ? Font.Normal : Font.Medium
                    color: root.compactMenu ? Tokens.menuMuted : Tokens.text_primary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: !!root.btAdapter && !root.isPowered && !root.isAdapterBlocked
                    text: "Turn Bluetooth on to see paired and nearby devices."
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                ActionButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.settingsPage && !root.compactMenu && !!root.btAdapter && !root.isPowered
                    text: root.isPowerPending ? "Turning on…" : "Turn Bluetooth on"
                    accessibleLabel: text
                    emphasized: true
                    actionable: !root.isPowerPending && !root.isConnecting && !root.isForgetPending
                    onActivated: root.requestAdapterPower(true)
                }

                ActionButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.settingsPage && !root.compactMenu && !!root.btAdapter && root.isPowered && root.devices.length === 0 && !root.isScanning
                    text: "Scan for devices"
                    accessibleLabel: text
                    emphasized: true
                    actionable: !root.isPowerPending && !root.isConnecting && !root.isForgetPending
                    onActivated: root.startScan()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            visible: root.compactMenu
            color: Tokens.menuLine
        }

        Repeater {
            model: !root.compactMenu ? [] : root.isPowered ? ["scan", "settings"] : ["settings"]

            ItemDelegate {
                id: compactAction
                required property string modelData
                readonly property bool opensSettings: modelData === "settings"
                readonly property string glyph: opensSettings ? "󰒓" : "󰍉"
                Layout.fillWidth: true
                implicitHeight: 33
                leftPadding: 8
                rightPadding: 8
                hoverEnabled: true
                text: opensSettings ? qsTr("Bluetooth Settings")
                    : !root.isScanning ? qsTr("Find Nearby Devices")
                    : root.scanOwnedAdapter === root.btAdapter ? qsTr("Stop Scanning") : qsTr("Scanning…")
                enabled: opensSettings || (!root.isAdapterBlocked && !root.isAdapterTransitioning
                    && !root.isPowerPending && !root.isConnecting && !root.isForgetPending
                    && (!root.isScanning || root.scanOwnedAdapter === root.btAdapter))
                onClicked: {
                    if (opensSettings) root.requestSettings("bluetooth");
                    else root.toggleScan();
                }
                Keys.onReturnPressed: compactAction.clicked()
                HoverHandler { cursorShape: compactAction.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

                contentItem: RowLayout {
                    spacing: 9
                    Text {
                        text: compactAction.glyph
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        color: Tokens.menuMuted
                        Accessible.ignored: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: compactAction.text
                        font.pixelSize: 13
                        color: !compactAction.enabled ? Tokens.menuMuted
                            : compactAction.hovered || compactAction.visualFocus ? Tokens.menuAccent : Tokens.menuText
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: compactAction.opensSettings
                        text: "›"
                        font.pixelSize: 15
                        color: Tokens.menuMuted
                        Accessible.ignored: true
                    }
                }

                background: Rectangle {
                    radius: 10
                    color: compactAction.hovered && compactAction.enabled ? Tokens.menuHover : "transparent"
                    border.width: compactAction.visualFocus ? 2 : 0
                    border.color: Tokens.menuAccent
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.actionMessage.length > 0 || (root.statusMessage.length > 0
                && (!root.settingsPage || root.statusMessage !== "Bluetooth is off")
                && (!root.compactMenu || !root.statusMessage.startsWith("Scanning for Bluetooth devices")))
            text: root.actionMessage.length > 0 ? root.actionMessage : root.statusMessage
            font.pixelSize: 11
                color: root.isErrorMessage(root.actionMessage.length > 0 ? root.actionMessage : root.statusMessage)
                    ? Tokens.danger : Tokens.text_secondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
    }

    Component {
        id: deviceCard

        Item {
            id: card
            required property var modelData
            property bool expanded: root.expandedDeviceKey === modelData.key
            readonly property bool working: root.isConnecting && root.activeDeviceMac === modelData.mac
            readonly property bool canActivate: root.isPowered && !root.isConnecting && !root.isPowerPending
                && !root.isForgetPending && !modelData.blocked
            readonly property string actionLabel: modelData.connected ? qsTr("Disconnect")
                : modelData.paired ? qsTr("Connect") : qsTr("Pair")
            implicitHeight: root.compactMenu ? cardContent.implicitHeight + 4
                : cardContent.implicitHeight + (root.settingsPage ? 24 : 0)
            Layout.fillWidth: true
            objectName: "bluetoothDevice_" + modelData.mac.replace(/:/g, "_")
            Accessible.name: modelData.name + ", " + root.deviceStatus(modelData)
            Accessible.role: root.compactMenu ? Accessible.Button : Accessible.Pane
            Accessible.description: root.compactMenu && card.canActivate ? card.actionLabel : ""
            Accessible.onPressAction: card.activateCompact()
            activeFocusOnTab: true
            Keys.onPressed: (event) => {
                if (root.compactMenu && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space)) {
                    card.activateCompact();
                    event.accepted = true;
                }
            }

            function activateCompact(): void {
                if (root.compactMenu && canActivate) root.connectDevice(modelData);
            }

            MouseArea {
                visible: root.compactMenu
                enabled: card.canActivate
                x: cardContent.x + deviceHeader.x
                y: cardContent.y + deviceHeader.y
                width: compactDeviceDetails.visible ? compactDeviceDetails.x : deviceHeader.width
                height: deviceHeader.height
                cursorShape: Qt.PointingHandCursor
                z: 1
                onClicked: card.activateCompact()
            }

            Rectangle {
                anchors.fill: parent
                radius: root.compactMenu ? 8 : root.settingsPage ? 9 : 12
                color: root.compactMenu ? (card.expanded || modelData.connected
                    ? Tokens.menuSelected
                    : rowHover.hovered
                        ? Tokens.menuHover : "transparent")
                    : root.settingsPage ? (rowHover.hovered ? Tokens.surface : Tokens.surface_low)
                    : rowHover.hovered
                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.86)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.54)
                border.color: root.compactMenu ? (card.activeFocus ? Tokens.menuAccent : "transparent")
                    : root.settingsPage ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)
                    : modelData.connected
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.42)
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.22)
                border.width: root.compactMenu ? (card.activeFocus ? 2 : 0) : root.settingsPage || modelData.connected ? 1 : 0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            HoverHandler { id: rowHover }

            ColumnLayout {
                id: cardContent
                anchors.fill: parent
                anchors.leftMargin: root.compactMenu ? 4 : root.settingsPage ? 12 : 8
                anchors.rightMargin: root.compactMenu ? 4 : root.settingsPage ? 12 : 8
                anchors.topMargin: root.compactMenu ? 2 : root.settingsPage ? 12 : 8
                anchors.bottomMargin: root.compactMenu ? 2 : root.settingsPage ? 12 : 8
                spacing: 4

                RowLayout {
                    id: deviceHeader
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.compactMenu ? 31 : root.settingsPage ? 42 : 48
                    spacing: 8

                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26

                        Rectangle {
                            objectName: root.compactMenu
                                ? "bluetoothDeviceBadge_" + modelData.mac.replace(/:/g, "_") : ""
                            anchors.centerIn: parent
                            width: root.compactMenu ? 24 : parent.width
                            height: root.compactMenu ? 24 : parent.height
                            radius: width / 2
                            color: modelData.connected ? Tokens.menuAccent : Tokens.menuHover
                        }

                        Image {
                            anchors.centerIn: parent
                            visible: !root.compactMenu && modelData.iconName.length > 0
                            source: visible ? Quickshell.iconPath(modelData.iconName, "bluetooth") : ""
                            sourceSize: Qt.size(26, 26)
                            fillMode: Image.PreserveAspectFit
                            width: 26
                            height: 26
                            Accessible.ignored: true
                        }

                        Text {
                            objectName: root.compactMenu
                                ? "bluetoothDeviceGlyph_" + modelData.mac.replace(/:/g, "_") : ""
                            anchors.centerIn: parent
                            visible: root.compactMenu || modelData.iconName.length === 0
                            text: root.getDeviceIcon(modelData.name, modelData.iconName)
                            font.family: root.compactMenu ? "JetBrainsMono Nerd Font" : ""
                            font.pixelSize: root.compactMenu ? 14 : 20
                            color: root.compactMenu
                                ? modelData.connected ? Tokens.on_accent : Tokens.menuMuted
                                : modelData.connected ? Tokens.accent : Tokens.text_secondary
                            Accessible.ignored: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            text: modelData.name
                            font.pixelSize: root.settingsPage ? 14 : 13
                            font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                            color: root.compactMenu ? Tokens.menuText : Tokens.text_primary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMenu || modelData.blocked
                            text: root.compactMenu ? qsTr("Blocked") : root.deviceStatus(modelData)
                            font.pixelSize: root.compactMenu ? 11 : root.settingsPage ? 12 : 10
                            color: modelData.connected ? Tokens.accent : Tokens.text_secondary
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        visible: root.compactMenu && modelData.connected && modelData.batteryPercent !== null
                            && !card.working
                        spacing: 3
                        Text {
                            text: modelData.batteryPercent === null ? "" : modelData.batteryPercent + "%"
                            font.pixelSize: 12
                            color: root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary
                        }
                        Text {
                            text: "󰁹"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            color: root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary
                            Accessible.ignored: true
                        }
                    }

                    Text {
                        visible: root.compactMenu && (card.working || (!modelData.connected && !modelData.blocked))
                        text: card.working ? qsTr("Working…") : card.actionLabel
                        font.pixelSize: 11
                        color: card.working || (card.canActivate && !modelData.paired) ? Tokens.menuAccent : Tokens.menuMuted
                    }

                    ToolButton {
                        id: compactDeviceDetails
                        visible: root.compactMenu && modelData.paired
                        implicitWidth: 28
                        implicitHeight: 28
                        Accessible.name: (card.expanded ? qsTr("Hide details for %1")
                            : qsTr("Show details for %1")).arg(card.modelData.name)
                        Accessible.expandable: true
                        Accessible.expanded: card.expanded
                        onClicked: root.expandedDeviceKey = card.expanded ? "" : card.modelData.key
                        Keys.onReturnPressed: compactDeviceDetails.clicked()
                        Keys.onEnterPressed: compactDeviceDetails.clicked()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        contentItem: Text {
                            text: card.expanded ? "−" : "⋯"
                            font.pixelSize: 16
                            color: compactDeviceDetails.hovered ? Tokens.menuAccent : Tokens.menuMuted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 7
                            color: compactDeviceDetails.hovered ? Tokens.menuHover : "transparent"
                            border.width: compactDeviceDetails.visualFocus ? 2 : 0
                            border.color: Tokens.menuAccent
                        }
                    }

                    ActionButton {
                        visible: !root.compactMenu
                        text: card.working ? "Working…" : card.actionLabel
                        accessibleLabel: modelData.connected
                            ? "Disconnect from " + modelData.name
                            : (modelData.paired ? "Connect to " : "Pair with ") + modelData.name
                        emphasized: !modelData.connected && !modelData.blocked
                        actionable: root.isPowered && !root.isConnecting && !root.isPowerPending
                            && !root.isForgetPending && !modelData.blocked
                        onActivated: root.connectDevice(modelData)
                    }

                    ActionButton {
                        visible: !root.compactMenu
                        text: card.expanded ? "Hide" : "Details"
                        accessibleLabel: (card.expanded ? "Hide details for " : "Show details for ") + modelData.name
                        actionable: !root.isPowerPending && !root.isForgetPending
                        onActivated: root.expandedDeviceKey = card.expanded ? "" : modelData.key
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: card.expanded
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: (root.compactMenu ? "" : root.deviceStatus(modelData) + " · ")
                            + (modelData.paired ? qsTr("Paired") : qsTr("Not paired"))
                            + " · " + (modelData.trusted ? qsTr("Trusted") : qsTr("Not trusted"))
                            + (modelData.blocked ? " · " + qsTr("Blocked") : "")
                        font.pixelSize: 10
                        color: modelData.blocked ? Tokens.danger : Tokens.text_secondary
                        elide: Text.ElideRight
                    }

                    ActionButton {
                        visible: modelData.paired
                        text: "Forget"
                        accessibleLabel: "Forget " + modelData.name
                        danger: true
                        actionable: !modelData.connected && !root.isConnecting
                            && !root.isPowerPending && !root.isForgetPending
                        onActivated: root.requestForget(modelData)
                    }

                }
            }
        }

    }

    Rectangle {
        id: deviceDialog
        anchors.fill: parent
        visible: root.forgetDialogOpen || root.pairingPromptType.length > 0
        color: Qt.rgba(0, 0, 0, 0.58)
        z: 10
        Accessible.role: Accessible.Dialog
        Accessible.focusable: true
        Accessible.name: root.forgetDialogOpen ? "Confirm Bluetooth device removal" : "Bluetooth pairing request"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Rectangle {
            id: dialogCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 24, 340)
            height: root.forgetDialogOpen ? 172
                : (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey" ? 216 : 184)
            radius: 16
            color: Tokens.surface_high
            border.color: root.forgetDialogOpen
                ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.58)
                : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.55)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.forgetDialogOpen ? "Forget this device?" : "Bluetooth pairing"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Tokens.text_primary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.forgetDialogOpen
                        ? "Remove the saved pairing for " + (root.pendingForgetDevice ? root.pendingForgetDevice.name : "this device") + "?"
                        : root.pairingPromptText
                    font.pixelSize: 12
                    color: Tokens.text_secondary
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: !root.forgetDialogOpen
                        && (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey")
                    radius: 9
                    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.72)
                    border.color: pairingInput.activeFocus ? Tokens.accent : Tokens.outline
                    border.width: pairingInput.activeFocus ? 2 : 1

                    TextInput {
                        id: pairingInput
                        anchors.fill: parent
                        anchors.margins: 10
                        enabled: parent.visible
                        visible: parent.visible
                        text: root.pairingInputText
                        color: Tokens.text_primary
                        font.pixelSize: 13
                        selectByMouse: true
                        inputMethodHints: root.pairingPromptType === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNoPredictiveText
                        Accessible.name: root.pairingPromptType === "passkey" ? "Bluetooth passkey" : "Bluetooth PIN"
                        Accessible.role: Accessible.EditableText
                        Accessible.passwordEdit: false
                        onTextChanged: root.pairingInputText = text
                        onAccepted: root.answerPairing(true)
                        Component.onCompleted: if (visible) forceActiveFocus()
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Keys.onEscapePressed: function(event) {
                            root.answerPairing(false);
                            event.accepted = true;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    ActionButton {
                        text: root.forgetDialogOpen ? "Cancel" : "Reject"
                        accessibleLabel: root.forgetDialogOpen ? "Cancel forgetting device" : "Reject Bluetooth pairing"
                        danger: !root.forgetDialogOpen
                        onActivated: root.forgetDialogOpen ? root.cancelForget() : root.answerPairing(false)
                    }

                    ActionButton {
                        text: root.forgetDialogOpen
                            ? "Forget"
                            : (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey" ? "Submit" : "Confirm")
                        accessibleLabel: root.forgetDialogOpen
                            ? "Confirm forget " + (root.pendingForgetDevice ? root.pendingForgetDevice.name : "device")
                            : (root.pairingPromptType === "pin" || root.pairingPromptType === "passkey" ? "Submit Bluetooth code" : "Confirm Bluetooth pairing")
                        emphasized: true
                        danger: root.forgetDialogOpen
                        actionable: root.forgetDialogOpen
                            ? !root.isForgetPending
                            : ((root.pairingPromptType !== "pin" && root.pairingPromptType !== "passkey")
                                || root.validatePairingInput(root.pairingPromptType, root.pairingInputText.trim()))
                        onActivated: root.forgetDialogOpen ? root.confirmForget() : root.answerPairing(true)
                    }
                }
            }
        }
    }
}
