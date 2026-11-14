pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool active: false
    property bool verifiedActive: false
    property string deviceName: ""
    readonly property string devicePath: deviceName
    property string tileStatus: "Checking…"
    property bool canStart: false
    property bool busy: false
    property bool available: false
    property bool canConfigure: false
    property bool profileConfigured: false
    property bool confirmationRequired: false
    property bool clientConflict: false
    property string ssid: ""
    property string security: ""
    property string upstreamStatus: "NetworkManager status is being checked."
    property string lifecycleState: "checking"
    property string errorMessage: ""
    property string pendingOperation: ""
    property var snapshot: ({})

    property int _requestSequence: 0
    property int _pendingRequest: -1
    property int _restartCount: 0
    property string _confirmationToken: ""

    signal operationFinished(string operation, bool ok, string message)

    function refresh(): void {
        sendRequest("status", {});
    }

    function toggle(): void {
        if (busy) return;
        confirmationRequired = false;
        _confirmationToken = "";
        errorMessage = "";
        if (active) {
            sendRequest("stop", {});
        } else if (canStart) {
            sendRequest("start", {});
        }
    }

    function saveConfiguration(networkName: string, password: string): bool {
        if (busy) return false;
        errorMessage = "";
        return sendRequest("configure", {ssid: networkName, password: password});
    }

    function confirmStart(): void {
        if (!confirmationRequired || _confirmationToken.length === 0 || busy) return;
        var token = _confirmationToken;
        confirmationRequired = false;
        _confirmationToken = "";
        errorMessage = "";
        sendRequest("start", {confirmationToken: token});
    }

    function cancelConfirmation(): void {
        confirmationRequired = false;
        _confirmationToken = "";
        errorMessage = "Start cancelled.";
    }

    function sendRequest(operation: string, details: var): bool {
        if (_pendingRequest >= 0 || !backendProcess.running) {
            if (!backendProcess.running) errorMessage = "NetworkManager service is unavailable.";
            return false;
        }
        _requestSequence += 1;
        var requestId = _requestSequence;
        var request = {requestId: requestId, op: operation};
        for (var key in details) request[key] = details[key];
        var serialized = JSON.stringify(request) + "\n";
        _pendingRequest = requestId;
        pendingOperation = operation;
        busy = operation !== "status";
        if (operation === "start") {
            lifecycleState = "starting";
            tileStatus = "Starting…";
        } else if (operation === "stop") {
            lifecycleState = "stopping";
            tileStatus = "Stopping…";
        }
        if (busy) operationTimeout.restart();
        backendProcess.write(serialized);
        request = null;
        serialized = "";
        return true;
    }

    function applySnapshot(snapshotValue: var): void {
        var oldDeviceName = deviceName;
        root.snapshot = snapshotValue;
        available = snapshotValue.available === true;
        active = snapshotValue.active === true;
        verifiedActive = snapshotValue.verifiedActive === true;
        canStart = snapshotValue.canStart === true;
        canConfigure = snapshotValue.canConfigure === true;
        profileConfigured = snapshotValue.profileConfigured === true;
        deviceName = String(snapshotValue.deviceName || "");
        tileStatus = String(snapshotValue.tileStatus || "Unavailable");
        ssid = String(snapshotValue.ssid || "");
        security = String(snapshotValue.security || "");
        upstreamStatus = String(snapshotValue.upstreamStatus || "");
        lifecycleState = String(snapshotValue.state || "unavailable");
        clientConflict = snapshotValue.clientConflict === true;
        if (snapshotValue.error) errorMessage = String(snapshotValue.error);
        if (confirmationRequired && (!clientConflict || oldDeviceName !== deviceName)) {
            confirmationRequired = false;
            _confirmationToken = "";
            errorMessage = "Wi-Fi state changed; review the hotspot before starting.";
        }
    }

    function handleBackendLine(line: string): void {
        var message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            errorMessage = "Hotspot service returned an invalid status.";
            return;
        }
        if (message.requestId !== undefined && message.requestId !== null) {
            if (message.requestId !== _pendingRequest) return;
            _pendingRequest = -1;
            operationTimeout.stop();
            busy = false;
        }
        if (message.snapshot) applySnapshot(message.snapshot);
        if (message.confirmationRequired === true) {
            confirmationRequired = true;
            _confirmationToken = String(message.confirmationToken || "");
        }
        if (message.error) errorMessage = String(message.error);
        else if (message.ok === true) errorMessage = "";
        if (message.requestId !== undefined && message.requestId !== null) {
            var operation = pendingOperation;
            pendingOperation = "";
            operationFinished(operation, message.ok === true,
                              String(message.error || ""));
        }
    }

    property Process backendProcess: Process {
        command: ["python3", Quickshell.shellDir + "/services/hotspot_backend.py"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handleBackendLine(line)
        }
        stderr: SplitParser {
            // The helper sends only credential-free diagnostics to stderr; discard them.
            onRead: _line => {}
        }
        onExited: (code) => {
            root.busy = false;
            root._pendingRequest = -1;
            root.pendingOperation = "";
            root.operationTimeout.stop();
            root.available = false;
            root.canStart = false;
            root.tileStatus = "NetworkManager service unavailable";
            if (root._restartCount < 1) {
                root._restartCount += 1;
                root.restartTimer.restart();
            } else {
                root.errorMessage = code === 0
                    ? "Hotspot service stopped." : "Hotspot service could not start.";
            }
        }
    }

    property Timer operationTimeout: Timer {
        interval: 30000
        repeat: false
        onTriggered: root.errorMessage = "NetworkManager is still processing the request."
    }

    property Timer restartTimer: Timer {
        interval: 1200
        repeat: false
        onTriggered: root.backendProcess.running = true
    }
}
