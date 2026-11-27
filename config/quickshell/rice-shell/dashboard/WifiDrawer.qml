pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../services"
import "../theme"

Item {
    id: root
    property bool settingsPage: false
    property bool compactMenu: false
    property bool otherNetworksExpanded: false
    readonly property bool canBrowseNetworks: !!root.wifiDevice && Networking.wifiEnabled
        && Networking.wifiHardwareEnabled && !root.hotspotBlocksSelectedWifi

    anchors.fill: settingsPage || compactMenu ? undefined : parent
    implicitWidth: 360
    implicitHeight: compactMenu ? Math.min(480, pageContent.implicitHeight)
        : settingsPage ? pageContent.implicitHeight : 480
    focus: visible && !settingsPage
    activeFocusOnTab: settingsPage
    property bool drawerOpen: true

    Accessible.role: Accessible.Pane
    Accessible.name: "Wi-Fi"

    signal closeRequested()
    signal requestSettings(string route)
    signal hotspotPageRequested()

    readonly property var wifiDevices: {
        var devices = Networking.devices.values;
        var result = [];
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi) result.push(devices[i]);
        }
        return result;
    }
    property var selectedWifiDevice: null
    readonly property string hotspotDevicePath: {
        try {
            return root.hotspotService && root.hotspotService.devicePath
                ? String(root.hotspotService.devicePath) : "";
        } catch (error) {
            return "";
        }
    }
    readonly property var hotspotService: {
        try {
            return typeof Hotspot === "undefined" ? null : Hotspot;
        } catch (error) {
            return null;
        }
    }
    readonly property bool hotspotActive: root.hotspotService !== null
        && (root.hotspotService.active === true || root.hotspotService.busy === true)
    readonly property var hotspotWifiDevice: {
        if (!root.hotspotActive || root.hotspotDevicePath.length === 0) return null;
        for (var i = 0; i < root.wifiDevices.length; i++) {
            var device = root.wifiDevices[i];
            if (device.name === root.hotspotDevicePath || device.address === root.hotspotDevicePath) {
                return device;
            }
        }
        return null;
    }
    readonly property var wifiDevice: {
        if (root.selectedWifiDevice && root.wifiDevices.indexOf(root.selectedWifiDevice) >= 0) {
            return root.selectedWifiDevice;
        }
        if (root.hotspotWifiDevice) return root.hotspotWifiDevice;
        for (var i = 0; i < root.wifiDevices.length; i++) {
            var device = root.wifiDevices[i];
            if (device.connected && device.mode === WifiDeviceMode.Station) return device;
        }
        for (var j = 0; j < root.wifiDevices.length; j++) {
            if (root.wifiDevices[j].mode === WifiDeviceMode.Station) return root.wifiDevices[j];
        }
        return root.wifiDevices.length > 0 ? root.wifiDevices[0] : null;
    }
    readonly property bool accessPointActive: root.wifiDevice !== null
        && root.wifiDevice.mode === WifiDeviceMode.AccessPoint
    // NetworkDevice has no NetworkManager object-path property. If an active
    // hotspot cannot be matched exactly to name/address, fail closed for Wi-Fi.
    readonly property bool hotspotBlocksSelectedWifi: root.accessPointActive
        || (root.hotspotActive
            && (!root.hotspotWifiDevice || root.wifiDevice === root.hotspotWifiDevice))
    readonly property bool hotspotDeviceIdentityUnknown: root.hotspotActive
        && root.hotspotWifiDevice === null
    readonly property bool radioOffBlocked: root.hotspotActive || root.accessPointActive

    function classifyNetworks(values) {
        var source = values || [];
        var decorated = [];
        for (var i = 0; i < source.length; i++) {
            var network = source[i];
            decorated.push({
                network: network,
                connected: network.connected,
                known: network.known,
                signal: network.signalStrength || 0,
                name: String(network.name || "").toLocaleLowerCase(),
                security: Number(network.security)
            });
        }
        decorated.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            var signalDifference = b.signal - a.signal;
            if (signalDifference !== 0) return signalDifference;
            if (a.name < b.name) return -1;
            if (a.name > b.name) return 1;
            return a.security - b.security;
        });

        var all = [];
        var known = [];
        var nearby = [];
        var connected = null;
        for (var j = 0; j < decorated.length; j++) {
            var sortedNetwork = decorated[j].network;
            all.push(sortedNetwork);
            if (decorated[j].connected) {
                if (!connected) connected = sortedNetwork;
            } else if (decorated[j].known) {
                known.push(sortedNetwork);
            } else {
                nearby.push(sortedNetwork);
            }
        }
        return { all: all, connected: connected, known: known, nearby: nearby };
    }
    readonly property var networkSnapshot: root.wifiDevice
        ? root.classifyNetworks(root.wifiDevice.networks.values)
        : { all: [], connected: null, known: [], nearby: [] }
    readonly property var networks: root.networkSnapshot.all
    readonly property var connectedNetwork: root.networkSnapshot.connected
    readonly property var knownNetworks: root.networkSnapshot.known
    readonly property var nearbyNetworks: root.networkSnapshot.nearby

    property var selectedNetwork: null
    property var detailsNetwork: null
    property var forgetConfirmationNetwork: null
    property var pendingForgetNetwork: null
    property var pendingNetwork: null
    property string pendingAction: ""
    property string passwordText: ""
    property string statusMessage: ""
    property bool showPassword: false
    property bool operationPending: false
    property bool operationTimedOut: false
    property var scanOwnedDevice: null
    property bool scanRequested: false
    readonly property bool isScanning: root.wifiDevice ? root.wifiDevice.scannerEnabled : false

    Binding {
        target: root.scanOwnedDevice
        property: "scannerEnabled"
        value: root.visible && root.scanRequested
        when: root.scanOwnedDevice !== null
    }

    onWifiDevicesChanged: {
        if (root.selectedWifiDevice && root.wifiDevices.indexOf(root.selectedWifiDevice) < 0) {
            root.selectedWifiDevice = null;
        }
    }

    onWifiDeviceChanged: {
        if (root.scanOwnedDevice && root.scanOwnedDevice !== root.wifiDevice) root.stopScan();
        if (root.selectedNetwork && root.selectedNetwork.device !== root.wifiDevice) {
            root.cancelPassword();
        }
        if (root.detailsNetwork && root.detailsNetwork.device !== root.wifiDevice) {
            root.detailsNetwork = null;
        }
        if (root.forgetConfirmationNetwork
                && root.forgetConfirmationNetwork.device !== root.wifiDevice) {
            root.forgetConfirmationNetwork = null;
        }
        if (root.pendingNetwork
                && root.wifiDevices.indexOf(root.pendingNetwork.device) < 0) {
            root.finishOperation("The Wi-Fi adapter changed while the request was pending.");
        }
        if (!root.wifiDevice) {
            root.cancelPassword();
            root.statusMessage = "Wi-Fi adapter unavailable";
        } else {
            if (root.statusMessage === "Wi-Fi adapter unavailable") root.statusMessage = "";
            if (root.visible && root.drawerOpen) {
                root.reconcilePendingOperation();
                root.scheduleScan();
            }
        }
    }

    onNetworksChanged: {
        if (root.selectedNetwork && !root.networkIsAvailable(root.selectedNetwork)) {
            root.cancelPassword();
        }
    }

    onAccessPointActiveChanged: {
        if (root.accessPointActive) root.stopScan();
        else if (root.visible && root.drawerOpen) root.scheduleScan();
    }

    onHotspotBlocksSelectedWifiChanged: {
        if (root.hotspotBlocksSelectedWifi) {
            root.stopScan();
            root.cancelPassword();
            root.statusMessage = root.hotspotStatusMessage();
        } else if (root.visible && root.drawerOpen) {
            root.scheduleScan();
        }
    }

    onDrawerOpenChanged: {
        if (root.drawerOpen && root.visible) {
            if (root.compactMenu) root.otherNetworksExpanded = false;
            root.reconcilePendingOperation();
            root.scheduleScan();
        } else {
            if (root.compactMenu) root.otherNetworksExpanded = false;
            root.stopScan();
        }
    }

    onVisibleChanged: {
        if (root.visible && root.drawerOpen) {
            root.reconcilePendingOperation();
            root.scheduleScan();
        } else {
            root.stopScan();
            root.cancelPassword();
            root.detailsNetwork = null;
            root.forgetConfirmationNetwork = null;
        }
    }

    Component.onCompleted: {
        root.reconcilePendingOperation();
        if (root.visible && root.drawerOpen) root.scheduleScan();
    }

    Component.onDestruction: {
        root.stopScan();
        root.cancelPassword();
    }

    Keys.onEscapePressed: function(event) {
        if (root.forgetConfirmationNetwork) {
            root.forgetConfirmationNetwork = null;
            event.accepted = true;
        } else if (root.selectedNetwork) {
            root.cancelPassword();
            event.accepted = true;
        } else if (root.detailsNetwork) {
            root.detailsNetwork = null;
            event.accepted = true;
        } else {
            root.closeRequested();
            event.accepted = true;
        }
    }

    function signalPercent(network): int {
        return Math.round(Math.max(0, Math.min(1, network.signalStrength || 0)) * 100);
    }

    function signalGlyph(network): string {
        var strength = network.signalStrength || 0;
        if (strength >= 0.75) return "󰤨";
        if (strength >= 0.5) return "󰤥";
        if (strength >= 0.25) return "󰤢";
        return "󰤟";
    }

    function securityLabel(network): string {
        switch (network.security) {
        case WifiSecurityType.Open: return "Open";
        case WifiSecurityType.WpaPsk: return "WPA Personal";
        case WifiSecurityType.Wpa2Psk: return "WPA2 Personal";
        case WifiSecurityType.Sae: return "WPA3 Personal";
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.Wpa3SuiteB192: return "Enterprise";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep: return "WEP (legacy)";
        case WifiSecurityType.Owe: return "Enhanced Open";
        case WifiSecurityType.Leap: return "LEAP";
        default: return "Security unknown";
        }
    }

    function supportsPsk(network): bool {
        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae;
    }

    function connectivityLabel(): string {
        if (!Networking.canCheckConnectivity || !Networking.connectivityCheckEnabled) {
            return "Not checked";
        }
        switch (Networking.connectivity) {
        case NetworkConnectivity.Full: return "Internet available";
        case NetworkConnectivity.Limited: return "Limited connectivity";
        case NetworkConnectivity.Portal: return "Sign-in required";
        case NetworkConnectivity.None: return "No network access";
        default: return "Unknown";
        }
    }

    function clearPassword(): void {
        root.passwordText = "";
        root.showPassword = false;
    }

    function cancelPassword(): void {
        root.selectedNetwork = null;
        root.clearPassword();
        if (!root.operationPending && !root.pendingForgetNetwork) root.statusMessage = "";
    }

    function promptForPassword(network, message): void {
        root.selectedNetwork = network;
        root.clearPassword();
        root.statusMessage = message || "";
    }

    function canOperate(): bool {
        return root.wifiDevice !== null
            && Networking.wifiEnabled
            && Networking.wifiHardwareEnabled
            && !root.hotspotBlocksSelectedWifi
            && !root.operationPending;
    }

    function networkIsAvailable(network): bool {
        if (!network || !network.device
                || root.wifiDevices.indexOf(network.device) < 0) return false;
        return network.device.networks.values.indexOf(network) >= 0;
    }

    function hotspotStatusMessage(): string {
        if (root.hotspotDeviceIdentityUnknown) {
            return "The active hotspot adapter could not be matched safely. Wi-Fi actions are paused.";
        }
        if (root.accessPointActive
                || (root.hotspotWifiDevice && root.hotspotWifiDevice === root.wifiDevice)) {
            return "Used by Hotspot. Open the Hotspot tab to stop it.";
        }
        return "The active hotspot adapter could not be matched safely. Wi-Fi actions are paused.";
    }

    function scheduleScan(): void {
        scanStartTimer.stop();
        if (!root.drawerOpen || !root.visible) return;
        scanStartTimer.restart();
    }

    function startScan(): void {
        if (!root.wifiDevice || !root.drawerOpen || !root.visible || !Networking.wifiEnabled) return;
        if (!Networking.wifiHardwareEnabled || root.hotspotBlocksSelectedWifi) return;
        if (root.wifiDevice.mode !== WifiDeviceMode.Station) return;
        if (root.wifiDevice.scannerEnabled) return;

        if (!root.operationPending && !root.pendingForgetNetwork) root.statusMessage = "";
        root.scanOwnedDevice = root.wifiDevice;
        root.scanRequested = true;
    }

    function stopScan(): void {
        scanStartTimer.stop();
        scanRestartTimer.stop();
        root.scanRequested = false;
        var owned = root.scanOwnedDevice;
        root.scanOwnedDevice = null;
        if (owned && owned.scannerEnabled) owned.scannerEnabled = false;
    }

    function scan(): void {
        if (!root.wifiDevice || !root.drawerOpen || !root.visible || !Networking.wifiEnabled) return;
        if (!Networking.wifiHardwareEnabled || root.hotspotBlocksSelectedWifi) {
            root.statusMessage = "Wi-Fi is unavailable while this adapter is used by Hotspot.";
            return;
        }
        if (root.wifiDevice.mode !== WifiDeviceMode.Station) {
            root.statusMessage = "Network scanning is unavailable in this Wi-Fi mode.";
            return;
        }
        if (root.wifiDevice.scannerEnabled && root.scanOwnedDevice !== root.wifiDevice) {
            root.statusMessage = "A scan started elsewhere is already running.";
            return;
        }

        root.statusMessage = "";
        if (!root.scanOwnedDevice) root.scanOwnedDevice = root.wifiDevice;
        root.scanRequested = false;
        scanRestartTimer.restart();
    }

    function beginOperation(network, action): void {
        root.pendingNetwork = network;
        root.pendingAction = action;
        root.operationPending = true;
        root.operationTimedOut = false;
        actionTimeout.restart();
    }

    function finishOperation(message): void {
        actionTimeout.stop();
        root.operationPending = false;
        root.operationTimedOut = false;
        root.pendingNetwork = null;
        root.pendingAction = "";
        if (message) root.statusMessage = message;
    }

    function reconcilePendingOperation(): void {
        if (root.operationPending || !root.wifiDevice) return;
        for (var i = 0; i < root.wifiDevices.length; i++) {
            var deviceNetworks = root.wifiDevices[i].networks.values;
            for (var j = 0; j < deviceNetworks.length; j++) {
                var network = deviceNetworks[j];
                if (!network.stateChanging) continue;
                root.pendingNetwork = network;
                root.pendingAction = network.state === ConnectionState.Connecting ? "connect" : "disconnect";
                root.operationPending = true;
                root.operationTimedOut = false;
                root.statusMessage = network.state === ConnectionState.Connecting
                    ? "Connecting to " + (network.name || "network") + "…"
                    : "Disconnecting from " + (network.name || "network") + "…";
                actionTimeout.restart();
                return;
            }
        }
    }

    function syncPendingOperation(): void {
        var network = root.pendingNetwork;
        if (!network || !root.operationPending) return;

        if (network.connected) {
            var name = network.name || "network";
            root.finishOperation("Connected to " + name);
            root.cancelPassword();
            return;
        }
        if (!network.stateChanging && root.pendingAction === "disconnect") {
            root.finishOperation("Disconnected from " + (network.name || "network"));
            return;
        }
        if (!network.stateChanging && root.pendingAction === "cancel") {
            root.finishOperation("Connection cancelled");
            return;
        }
        if (!network.stateChanging && root.operationTimedOut) {
            root.finishOperation("The connection request timed out.");
        }
    }

    function handleConnectionFailure(network, reason): void {
        if (!network || root.pendingNetwork !== network) return;
        actionTimeout.stop();
        root.operationPending = false;
        root.operationTimedOut = false;
        root.pendingNetwork = null;
        root.pendingAction = "";
        root.clearPassword();

        if (reason === ConnectionFailReason.NoSecrets && root.supportsPsk(network)) {
            root.promptForPassword(network, "Password required or rejected. Try again.");
        } else if (reason === ConnectionFailReason.NoSecrets) {
            root.statusMessage = "This network needs a configured NetworkManager profile.";
        } else if (reason === ConnectionFailReason.WifiAuthTimeout) {
            root.statusMessage = "Wi-Fi authentication timed out.";
        } else if (reason === ConnectionFailReason.WifiNetworkLost) {
            root.statusMessage = "The Wi-Fi network disappeared.";
        } else {
            root.statusMessage = "Could not connect to " + (network.name || "network") + ".";
        }
    }

    function connectNetwork(network, withPassword): void {
        if (!network || !root.canOperate()) return;

        if (network.stateChanging) {
            root.beginOperation(network,
                network.state === ConnectionState.Connecting ? "connect" : "disconnect");
            root.statusMessage = network.state === ConnectionState.Connecting
                ? "Connecting to " + (network.name || "network") + "…"
                : "Disconnecting from " + (network.name || "network") + "…";
            return;
        }
        if (network.connected) {
            root.disconnectNetwork(network);
            return;
        }
        if (root.supportsPsk(network) && !network.known && !withPassword) {
            root.promptForPassword(network, "");
            return;
        }
        if (!network.known && network.security !== WifiSecurityType.Open
                && !root.supportsPsk(network)) {
            root.statusMessage = "This security method needs a NetworkManager profile.";
            return;
        }
        if (withPassword && (!root.supportsPsk(network) || root.passwordText.length === 0)) {
            root.statusMessage = root.passwordText.length === 0
                ? "Enter a password." : "Password entry is unavailable for this security type.";
            return;
        }

        root.selectedNetwork = null;
        var secret = withPassword ? root.passwordText : "";
        root.clearPassword();
        root.beginOperation(network, "connect");
        root.statusMessage = "Connecting to " + (network.name || "network") + "…";
        try {
            if (withPassword) network.connectWithPsk(secret);
            else network.connect();
        } catch (error) {
            root.finishOperation("Could not start the Wi-Fi connection.");
        }
    }

    function disconnectNetwork(network): void {
        if (!network || !root.wifiDevice || !Networking.wifiEnabled
                || !Networking.wifiHardwareEnabled || root.hotspotBlocksSelectedWifi
                || root.operationPending) return;
        root.beginOperation(network, "disconnect");
        root.statusMessage = "Disconnecting from " + (network.name || "network") + "…";
        try {
            network.disconnect();
        } catch (error) {
            root.finishOperation("Could not disconnect from this network.");
        }
    }

    function cancelConnection(network): void {
        if (!network || !root.operationPending || root.pendingNetwork !== network
                || root.pendingAction !== "connect" || root.hotspotBlocksSelectedWifi) return;
        root.pendingAction = "cancel";
        root.statusMessage = "Cancelling connection to " + (network.name || "network") + "…";
        try {
            network.disconnect();
        } catch (error) {
            root.statusMessage = "Could not cancel the connection request.";
        }
    }

    function toggleDetails(network): void {
        root.cancelPassword();
        root.forgetConfirmationNetwork = null;
        root.detailsNetwork = root.detailsNetwork === network ? null : network;
    }

    function requestForget(network): void {
        if (!network || !network.known || root.hotspotBlocksSelectedWifi
                || root.operationPending || root.pendingForgetNetwork) return;
        root.cancelPassword();
        root.detailsNetwork = null;
        root.forgetConfirmationNetwork = network;
        root.statusMessage = "";
    }

    function forgetNetwork(network): void {
        if (!network || !network.known || root.hotspotBlocksSelectedWifi
                || root.operationPending || root.pendingForgetNetwork) return;
        root.forgetConfirmationNetwork = null;
        root.pendingForgetNetwork = network;
        root.statusMessage = "Removing saved connection settings…";
        forgetTimeout.restart();
        try {
            network.forget();
            Qt.callLater(function() {
                if (root.pendingForgetNetwork === network && !network.known) {
                    root.finishForget(true);
                }
            });
        } catch (error) {
            root.finishForget(false);
        }
    }

    function finishForget(success): void {
        forgetTimeout.stop();
        root.pendingForgetNetwork = null;
        root.statusMessage = success
            ? "Saved NetworkManager profiles removed."
            : "Could not confirm that saved profiles were removed.";
    }

    function setWifiEnabled(enabled): void {
        if (!root.wifiDevice || root.hotspotActive || root.accessPointActive
                || !Networking.wifiHardwareEnabled || root.operationPending) return;
        if (!enabled) {
            root.stopScan();
            root.cancelPassword();
        }
        Networking.wifiEnabled = enabled;
    }

    Connections {
        target: root.pendingNetwork
        ignoreUnknownSignals: true

        function onConnectedChanged(): void { root.syncPendingOperation(); }
        function onStateChangingChanged(): void { root.syncPendingOperation(); }
        function onConnectionFailed(reason): void {
            root.handleConnectionFailure(root.pendingNetwork, reason);
        }
    }

    Connections {
        target: root.pendingForgetNetwork
        ignoreUnknownSignals: true

        function onKnownChanged(): void {
            if (root.pendingForgetNetwork && !root.pendingForgetNetwork.known) {
                root.finishForget(true);
            }
        }
    }

    // shortcut: one 220ms deferral keeps NetworkManager work off initial drawer motion;
    // raise only if scans still hitch.
    Timer {
        id: scanStartTimer
        interval: 220
        repeat: false
        onTriggered: root.startScan()
    }

    Timer {
        id: scanRestartTimer
        interval: 220
        repeat: false
        onTriggered: root.scanRequested = true
    }

    Timer {
        id: actionTimeout
        interval: 30000
        repeat: false
        onTriggered: {
            if (!root.operationPending) return;
            if (root.pendingNetwork && root.pendingNetwork.stateChanging) {
                root.operationTimedOut = true;
                root.statusMessage = "Still waiting for NetworkManager. You can cancel this request.";
            } else {
                root.finishOperation("The Wi-Fi request timed out.");
            }
        }
    }

    Timer {
        id: forgetTimeout
        interval: 10000
        repeat: false
        onTriggered: root.finishForget(false)
    }

    ColumnLayout {
        id: pageContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: root.settingsPage ? undefined : parent.bottom
        spacing: root.compactMenu ? 6 : root.settingsPage ? 17 : 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.compactMenu ? Math.max(50, radioControls.implicitHeight + 12)
                : root.settingsPage ? Math.max(68, radioControls.implicitHeight + 20)
                : Math.max(38, radioControls.implicitHeight)
            radius: root.compactMenu ? 11 : 10
            color: root.compactMenu ? Qt.tint(Tokens.menuSurface, Qt.alpha(Tokens.menuAccent, 0.06))
                : root.settingsPage ? Tokens.surface_low : "transparent"
            border.width: root.settingsPage ? 1 : 0
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5)

            RowLayout {
                id: radioControls
                anchors.fill: parent
                anchors.leftMargin: root.compactMenu ? 8 : root.settingsPage ? 12 : 0
                anchors.rightMargin: anchors.leftMargin
                spacing: root.compactMenu ? 8 : 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    visible: root.compactMenu
                    radius: 9
                    color: Networking.wifiEnabled ? Tokens.menuSelected : Tokens.menuSurface
                    Accessible.ignored: true

                    Text {
                        anchors.centerIn: parent
                        text: Networking.wifiEnabled ? "󰤨" : "󰤭"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17
                        color: Networking.wifiEnabled ? Tokens.menuAccent : Tokens.menuMuted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: -1
                    spacing: 3
                    Text {
                        objectName: root.compactMenu ? "wifiCompactTitle" : ""
                        visible: root.settingsPage || root.compactMenu
                        text: root.compactMenu ? qsTr("Wi-Fi") : qsTr("Wi-Fi radio")
                        font.pixelSize: root.compactMenu ? 15 : 15
                        font.weight: Font.DemiBold
                        color: root.compactMenu ? Tokens.menuText : Tokens.text_primary
                    }
                    Text {
                        objectName: root.compactMenu ? "wifiCompactSubtitle" : ""
                        Layout.fillWidth: true
                        visible: root.compactMenu
                        elide: Text.ElideRight
                        text: !root.wifiDevice || !Networking.wifiHardwareEnabled ? qsTr("Unavailable")
                            : root.hotspotBlocksSelectedWifi ? qsTr("Unavailable while Hotspot is active")
                            : Networking.wifiEnabled
                                ? (root.connectedNetwork ? qsTr("Connected") : qsTr("On · not connected"))
                                : qsTr("Off")
                        font.pixelSize: 12
                        color: Tokens.menuMuted
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !root.compactMenu
                        text: !root.wifiDevice ? "Adapter unavailable"
                            : root.hotspotBlocksSelectedWifi ? root.hotspotStatusMessage()
                            : !Networking.wifiHardwareEnabled ? "Blocked by hardware switch"
                            : root.radioOffBlocked ? "Radio locked while Hotspot is active"
                            : Networking.wifiEnabled ? (root.settingsPage ? (root.connectedNetwork
                                ? root.connectivityLabel() : qsTr("No network connected")) : "Wi-Fi is on")
                                : (root.settingsPage ? qsTr("Wireless radio is off") : "Wi-Fi is off")
                        font.pixelSize: root.settingsPage ? 13 : 12
                        color: !root.settingsPage && (root.hotspotBlocksSelectedWifi || Networking.wifiEnabled)
                            ? Tokens.accent : Tokens.text_secondary
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }

                Item {
                    Layout.preferredWidth: root.compactMenu ? 44 : root.settingsPage ? (refreshButton.visible ? 153 : 44) : 84
                    Layout.preferredHeight: root.compactMenu ? 28 : 30
                    Layout.alignment: Qt.AlignVCenter

                    Row {
                        anchors.fill: parent
                        spacing: 10

                        Switch {
                            id: wifiSwitch
                            objectName: root.compactMenu ? "wifiCompactSwitch" : ""
                            width: root.compactMenu ? 38 : 44
                            height: root.compactMenu ? 22 : 24
                            implicitWidth: width
                            implicitHeight: height
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Networking.wifiEnabled
                            enabled: root.wifiDevice !== null
                                && Networking.wifiHardwareEnabled
                                && !root.radioOffBlocked
                                && !root.operationPending
                            Accessible.name: "Wi-Fi power"
                            onClicked: root.setWifiEnabled(checked)

                            indicator: Rectangle {
                                implicitWidth: root.compactMenu ? 38 : 44
                                implicitHeight: root.compactMenu ? 22 : 24
                                width: implicitWidth
                                height: implicitHeight
                                radius: height / 2
                                color: wifiSwitch.checked
                                    ? (root.compactMenu ? Tokens.menuSwitch : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.85))
                                    : (root.compactMenu ? Tokens.menuLine : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35))
                                border.color: wifiSwitch.activeFocus ? (root.compactMenu ? Tokens.menuAccent : Tokens.accent) : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 160 } }

                                Rectangle {
                                    width: root.compactMenu ? 16 : 18
                                    height: width
                                    radius: width / 2
                                    y: (parent.height - height) / 2
                                    x: wifiSwitch.checked ? parent.width - width - 3 : 3
                                    color: wifiSwitch.checked ? Tokens.on_accent : (root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary)
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            contentItem: Item {}
                        }

                        Rectangle {
                            id: refreshButton
                            visible: !root.compactMenu && (!root.settingsPage || Networking.wifiEnabled)
                            width: root.settingsPage ? 99 : 30
                            height: 30
                            radius: root.settingsPage ? 8 : 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: refreshHover.hovered
                                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                                : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.45)
                            border.color: refreshButton.activeFocus
                                ? Tokens.accent
                                : (refreshHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.3) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2))
                            border.width: 1
                            enabled: root.wifiDevice !== null && Networking.wifiEnabled
                                && Networking.wifiHardwareEnabled
                                && !root.hotspotBlocksSelectedWifi
                                && (!root.isScanning || root.scanOwnedDevice === root.wifiDevice)
                            Accessible.role: Accessible.Button
                            Accessible.name: "Refresh nearby Wi-Fi networks"

                            Text {
                                id: refreshIcon
                                anchors.centerIn: parent
                                text: root.settingsPage ? (root.isScanning ? qsTr("Scanning…") : qsTr("Scan networks")) : "󰑐"
                                font.pixelSize: root.settingsPage ? 12 : 15
                                color: refreshButton.enabled ? (root.isScanning ? Tokens.accent : Tokens.text_primary) : Tokens.text_secondary
                                RotationAnimator {
                                    target: refreshIcon
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    running: root.isScanning && !root.settingsPage
                                }
                            }

                            HoverHandler { id: refreshHover; cursorShape: refreshButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler {
                                enabled: refreshButton.enabled
                                onTapped: root.scan()
                            }
                        }
                    }
                }
            }
        }

        ComboBox {
            id: adapterSelector
            Layout.fillWidth: true
            visible: !root.compactMenu && root.wifiDevices.length > 1
            model: root.wifiDevices.map(function(device) { return device.name; })
            currentIndex: Math.max(0, root.wifiDevices.indexOf(root.wifiDevice))
            Accessible.name: "Wi-Fi adapter"
            delegate: ItemDelegate {
                required property var modelData
                width: adapterSelector.width
                text: String(modelData)
                Accessible.name: text
                contentItem: Text {
                    text: parent.text
                    font.pixelSize: 12
                    color: Tokens.text_primary
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    verticalAlignment: Text.AlignVCenter
                }
            }
            onActivated: function(index) {
                root.stopScan();
                root.selectedWifiDevice = root.wifiDevices[index] || null;
                root.statusMessage = "";
                root.startScan();
            }

            background: Rectangle {
                radius: 9
                color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.35)
                border.color: adapterSelector.activeFocus ? Tokens.accent : Tokens.outline
                border.width: adapterSelector.activeFocus ? 2 : 1
            }
            contentItem: Text {
                leftPadding: 10
                rightPadding: 30
                text: adapterSelector.displayText
                font.pixelSize: 12
                color: Tokens.text_primary
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.compactMenu && root.canBrowseNetworks
            implicitHeight: 1
            color: Tokens.menuLine
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.hotspotBlocksSelectedWifi && !root.compactMenu
            implicitHeight: hotspotNotice.implicitHeight + 20
            radius: 11
            color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.1)
            border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.28)
            border.width: 1

            RowLayout {
                id: hotspotNotice
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Text {
                    text: "󰐼"
                    font.pixelSize: 20
                    color: Tokens.accent
                    Accessible.ignored: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hotspotStatusMessage()
                    font.pixelSize: 11
                    color: Tokens.text_primary
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                RoundedButton {
                    text: "Hotspot"
                    Accessible.name: "Open Hotspot tab"
                    onClicked: root.hotspotPageRequested()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: root.compactMenu ? 12 : 0
            Layout.rightMargin: root.compactMenu ? 12 : 0
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            font.pixelSize: 11
            color: root.compactMenu ? Tokens.menuAccent : Tokens.accent
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Rectangle {
            visible: !root.settingsPage && !root.compactMenu
            Layout.fillWidth: true
            implicitHeight: 42
            radius: 12
            color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.32)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.22)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Networking.connectivity === NetworkConnectivity.Full
                        ? Tokens.accent
                        : (Networking.connectivity === NetworkConnectivity.Limited
                            ? Qt.rgba(0.95, 0.77, 0.48, 1.0)
                            : (Networking.connectivity === NetworkConnectivity.Portal
                                ? Qt.rgba(0.95, 0.77, 0.48, 1.0)
                                : Tokens.text_secondary))
                }

                Text {
                    text: "Internet"
                    font.pixelSize: 12
                    font.bold: true
                    color: Tokens.text_primary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.connectivityLabel()
                    font.pixelSize: 11
                    color: Networking.connectivity === NetworkConnectivity.Full ? Tokens.accent : Tokens.text_secondary
                }
            }
        }

        Flickable {
            id: pageFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            visible: !root.compactMenu || root.canBrowseNetworks
            contentWidth: width
            Layout.preferredHeight: root.compactMenu ? Math.min(contentHeight, 300)
                : root.settingsPage ? contentHeight : -1
            interactive: !root.settingsPage
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: root.settingsPage ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

            ColumnLayout {
                id: contentColumn
                width: pageFlick.width
                spacing: root.compactMenu ? 2 : 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.compactMenu ? 8 : 0
                    Layout.rightMargin: root.compactMenu ? 8 : 0
                    visible: root.connectedNetwork !== null

                    Text {
                        text: root.compactMenu ? qsTr("Current Network") : "Current connection"
                        font.capitalization: root.settingsPage || root.compactMenu ? Font.MixedCase : Font.AllUppercase
                        font.letterSpacing: root.settingsPage || root.compactMenu ? 0 : 1.1
                        font.pixelSize: root.settingsPage ? 15 : root.compactMenu ? 12 : 10
                        font.weight: root.compactMenu ? Font.Medium : Font.DemiBold
                        color: root.compactMenu ? Tokens.menuMuted : root.settingsPage ? Tokens.text_primary
                            : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.75)
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !root.settingsPage && !root.compactMenu
                        text: root.wifiDevice ? root.wifiDevice.name : ""
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                        textFormat: Text.PlainText
                    }
                }

                Repeater {
                    model: root.connectedNetwork ? [root.connectedNetwork] : []
                    delegate: networkRowDelegate
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.compactMenu ? 8 : 0
                    Layout.rightMargin: root.compactMenu ? 8 : 0
                    visible: !root.compactMenu && !root.settingsPage && !root.connectedNetwork && !!root.wifiDevice && Networking.wifiEnabled
                        && Networking.wifiHardwareEnabled && !root.hotspotBlocksSelectedWifi
                    text: "Not connected to a Wi-Fi network."
                    font.pixelSize: 12
                    color: Tokens.text_secondary
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.compactMenu ? 8 : 0
                    Layout.topMargin: root.compactMenu && root.connectedNetwork ? 5 : 0
                    text: root.compactMenu ? qsTr("Known Networks")
                        : root.settingsPage ? qsTr("Saved networks") : "Saved & in range"
                    visible: root.knownNetworks.length > 0
                    font.capitalization: root.settingsPage || root.compactMenu ? Font.MixedCase : Font.AllUppercase
                    font.letterSpacing: root.settingsPage || root.compactMenu ? 0 : 1.1
                    font.pixelSize: root.settingsPage ? 15 : root.compactMenu ? 12 : 10
                    font.bold: true
                    color: root.compactMenu ? Tokens.menuMuted : root.settingsPage ? Tokens.text_primary : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.65)
                }

                Repeater {
                    model: root.knownNetworks
                    delegate: networkRowDelegate
                }

                ItemDelegate {
                    id: otherNetworksToggle
                    objectName: root.compactMenu ? "wifiCompactOtherNetworks" : ""
                    Layout.fillWidth: true
                    visible: root.compactMenu && root.canBrowseNetworks
                    Layout.topMargin: root.connectedNetwork || root.knownNetworks.length > 0 ? 3 : 0
                    implicitHeight: 31
                    leftPadding: 8
                    rightPadding: 8
                    Accessible.name: root.otherNetworksExpanded ? qsTr("Hide other networks") : qsTr("Show other networks")
                    Accessible.expandable: true
                    Accessible.expanded: root.otherNetworksExpanded
                    onClicked: {
                        if (root.otherNetworksExpanded && root.selectedNetwork
                                && root.nearbyNetworks.includes(root.selectedNetwork)) root.cancelPassword();
                        root.otherNetworksExpanded = !root.otherNetworksExpanded;
                    }
                    Keys.onReturnPressed: otherNetworksToggle.clicked()
                    contentItem: RowLayout {
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Other Networks")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: otherNetworksToggle.hovered || otherNetworksToggle.visualFocus
                                ? Tokens.menuAccent : Tokens.menuText
                        }
                        Text {
                            visible: root.nearbyNetworks.length > 0
                            text: String(root.nearbyNetworks.length)
                            font.pixelSize: 11
                            color: Tokens.menuMuted
                            Accessible.ignored: true
                        }
                        Text {
                            text: root.otherNetworksExpanded ? "⌄" : "›"
                            font.pixelSize: 15
                            color: Tokens.menuMuted
                        }
                    }
                    background: Rectangle {
                        radius: 10
                        color: otherNetworksToggle.hovered ? Tokens.menuHover : "transparent"
                        border.color: otherNetworksToggle.visualFocus ? Tokens.menuAccent : "transparent"
                        border.width: otherNetworksToggle.visualFocus ? 2 : 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.compactMenu && !root.settingsPage && Networking.wifiEnabled && root.wifiDevice
                        && root.knownNetworks.length === 0 && root.nearbyNetworks.length === 0
                        && !root.isScanning && !root.hotspotBlocksSelectedWifi
                    text: "No saved networks are currently in range."
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                    textFormat: Text.PlainText
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.compactMenu && root.nearbyNetworks.length > 0
                    text: "Nearby networks"
                    font.capitalization: root.settingsPage ? Font.MixedCase : Font.AllUppercase
                    font.letterSpacing: root.settingsPage ? 0 : 1.1
                    font.pixelSize: root.settingsPage ? 15 : 10
                    font.bold: true
                    color: root.settingsPage ? Tokens.text_primary : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.65)
                }

                Repeater {
                    model: !root.compactMenu || root.otherNetworksExpanded ? root.nearbyNetworks : []
                    delegate: networkRowDelegate
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.compactMenu ? 12 : 0
                    Layout.rightMargin: root.compactMenu ? 12 : 0
                    visible: root.wifiDevice !== null && Networking.wifiEnabled
                        && !root.hotspotBlocksSelectedWifi && root.isScanning
                        && (!root.compactMenu || root.otherNetworksExpanded)
                    spacing: 8

                    BusyIndicator {
                        objectName: root.compactMenu ? "wifiCompactScanIndicator" : ""
                        visible: !root.compactMenu
                        running: visible
                        implicitWidth: 20
                        implicitHeight: 20
                    }

                    Text {
                        objectName: root.compactMenu ? "wifiCompactScanningText" : ""
                        text: "Scanning nearby networks…"
                        font.pixelSize: 11
                        color: root.compactMenu ? Tokens.menuMuted : Tokens.text_secondary
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.settingsPage && Networking.wifiEnabled && Networking.wifiHardwareEnabled
                        && !!root.wifiDevice && !root.hotspotBlocksSelectedWifi && !root.isScanning
                        && root.nearbyNetworks.length === 0
                    text: qsTr("No other networks found. Scan to refresh.")
                    font.pixelSize: 13
                    color: Tokens.text_secondary
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    visible: root.compactMenu && root.otherNetworksExpanded && !root.isScanning && root.nearbyNetworks.length === 0
                    text: qsTr("No nearby networks found")
                    color: Tokens.menuMuted
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true; implicitHeight: 2 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.compactMenu
            implicitHeight: 1
            color: Tokens.menuLine
        }

        ItemDelegate {
            id: wifiSettingsLink
            objectName: root.compactMenu ? "wifiCompactSettings" : ""
            Layout.fillWidth: true
            visible: root.compactMenu
            implicitHeight: 33
            leftPadding: 8
            rightPadding: 8
            Accessible.name: qsTr("Open Wi-Fi Settings")
            Keys.onReturnPressed: wifiSettingsLink.clicked()
            onClicked: root.requestSettings("network#wifi")
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            contentItem: RowLayout {
                spacing: 9
                Text {
                    text: "󰒓"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    color: Tokens.menuMuted
                    Accessible.ignored: true
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Wi-Fi Settings")
                    font.pixelSize: 13
                    color: wifiSettingsLink.hovered || wifiSettingsLink.visualFocus
                        ? Tokens.menuAccent : Tokens.menuText
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    objectName: root.compactMenu ? "wifiCompactFooterArrow" : ""
                    text: "›"
                    font.pixelSize: 15
                    color: Tokens.menuMuted
                    Accessible.ignored: true
                }
            }
            background: Rectangle {
                radius: 10
                color: wifiSettingsLink.hovered
                        ? Tokens.menuHover : "transparent"
                border.color: wifiSettingsLink.visualFocus ? Tokens.menuAccent : "transparent"
                border.width: wifiSettingsLink.visualFocus ? 2 : 0
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }

    Component {
        id: networkRowDelegate

        Rectangle {
            id: networkRow
            objectName: root.compactMenu ? "wifiCompactNetworkRow" : ""
            required property var modelData

            property var network: modelData
            readonly property bool isCurrent: network.connected
            readonly property bool passwordPrompt: root.selectedNetwork === network
            readonly property bool showingDetails: root.detailsNetwork === network
            readonly property bool confirmingForget: root.forgetConfirmationNetwork === network
            readonly property bool ownOperation: root.operationPending && root.pendingNetwork === network

            Layout.fillWidth: true
            implicitHeight: root.compactMenu ? Math.max(networkRow.isCurrent ? 41 : 34, rowContents.implicitHeight + 8)
                : rowContents.implicitHeight + (root.settingsPage ? 26 : 14)
            radius: root.compactMenu ? 8 : root.settingsPage ? 9 : 12
            color: root.compactMenu ? (networkRow.isCurrent
                ? Tokens.menuSelected
                : rowHover.hovered
                    ? Tokens.menuHover
                    : "transparent")
                : root.settingsPage ? (rowHover.hovered ? Tokens.surface : Tokens.surface_low) : isCurrent
                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.10)
                : (rowHover.hovered
                    ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.45)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.22))
            border.color: root.compactMenu ? (networkRow.activeFocus ? Tokens.menuAccent : "transparent") : root.settingsPage && !networkRow.activeFocus
                ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.5) : isCurrent
                ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.35)
                : (networkRow.activeFocus ? Tokens.accent
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.20))
            border.width: networkRow.activeFocus ? 2 : root.compactMenu ? 0 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            HoverHandler { id: rowHover; cursorShape: root.compactMenu ? Qt.PointingHandCursor : Qt.ArrowCursor }
            Accessible.role: root.compactMenu ? Accessible.Button : Accessible.ListItem
            Accessible.name: (network.name || "Hidden network")
                + (network.connected ? ", connected" : "")
                + (network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.None
                    ? ", secured" : "")
            activeFocusOnTab: root.compactMenu
            Accessible.onPressAction: networkRow.activateCompact()
            Keys.onPressed: (event) => {
                if (root.compactMenu && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) && !networkRow.passwordPrompt) {
                    networkRow.activateCompact();
                    event.accepted = true;
                }
            }

            function activateCompact(): void {
                if (!root.compactMenu || passwordPrompt) return;
                if (ownOperation && root.pendingAction === "connect") root.cancelConnection(network);
                else root.connectNetwork(network, false);
            }

            MouseArea {
                enabled: root.compactMenu && !networkRow.passwordPrompt
                    && (root.canOperate() || (networkRow.ownOperation && root.pendingAction === "connect"))
                visible: root.compactMenu
                x: rowContents.x + networkHeader.x
                y: rowContents.y + networkHeader.y
                width: compactWifiDetails.visible ? compactWifiDetails.x : networkHeader.width
                height: networkHeader.height
                cursorShape: Qt.PointingHandCursor
                z: 1
                onClicked: networkRow.activateCompact()
            }

            ColumnLayout {
                id: rowContents
                anchors.fill: parent
                anchors.margins: root.compactMenu ? 4 : root.settingsPage ? 13 : 10
                spacing: root.compactMenu ? 5 : 8

                RowLayout {
                    id: networkHeader
                    Layout.fillWidth: true
                    spacing: 10

                    Row {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            visible: !root.compactMenu && !root.settingsPage && networkRow.network.security !== WifiSecurityType.Open
                                && networkRow.network.security !== WifiSecurityType.None
                            text: "󰌾"
                            font.pixelSize: 11
                            color: networkRow.isCurrent ? Tokens.accent : Qt.rgba(Tokens.text_secondary.r, Tokens.text_secondary.g, Tokens.text_secondary.b, 0.7)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: !root.compactMenu
                            text: root.signalGlyph(networkRow.network)
                            font.family: root.settingsPage || root.compactMenu ? "JetBrainsMono Nerd Font" : ""
                            font.pixelSize: root.settingsPage ? 22 : 18
                            color: networkRow.isCurrent ? Tokens.accent : Tokens.text_secondary
                            anchors.verticalCenter: parent.verticalCenter
                            Accessible.ignored: true
                        }

                        Rectangle {
                            visible: root.compactMenu
                            width: 24
                            height: 24
                            radius: 12
                            color: networkRow.isCurrent ? Tokens.menuAccent : Tokens.menuHover
                            Text {
                                anchors.centerIn: parent
                                text: root.signalGlyph(networkRow.network)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                color: networkRow.isCurrent ? Tokens.on_accent : Tokens.menuMuted
                                Accessible.ignored: true
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: networkRow.network.name || "Hidden network"
                            font.pixelSize: root.compactMenu ? 13 : root.settingsPage ? 14 : 13
                            font.weight: root.settingsPage || networkRow.isCurrent ? Font.DemiBold : Font.Normal
                            color: root.compactMenu ? Tokens.menuText : Tokens.text_primary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMenu || networkRow.isCurrent || networkRow.ownOperation
                            text: root.compactMenu
                                ? (networkRow.ownOperation && root.pendingAction === "connect"
                                    ? qsTr("Connecting… · Click to cancel")
                                    : qsTr("%1% signal").arg(root.signalPercent(networkRow.network)))
                                : root.securityLabel(networkRow.network)
                                    + (!root.settingsPage && networkRow.network.known ? " · Saved" : "")
                                    + (networkRow.isCurrent ? " · Connected" : "")
                            font.pixelSize: root.settingsPage ? 12 : 10
                            color: root.compactMenu ? (networkRow.isCurrent ? Tokens.menuAccent : Tokens.menuMuted) : !root.settingsPage && networkRow.isCurrent ? Tokens.accent : Tokens.text_secondary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }

                    Text {
                        visible: root.compactMenu && networkRow.network.security !== WifiSecurityType.Open
                            && networkRow.network.security !== WifiSecurityType.None
                            && !networkRow.isCurrent
                        text: "󰌾"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        color: Tokens.menuMuted
                        Accessible.name: "Secured network"
                    }

                    Text {
                        objectName: root.compactMenu ? "wifiCompactSelectionMark" : ""
                        visible: root.compactMenu && networkRow.isCurrent
                        text: "✓"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Tokens.menuAccent
                        Accessible.name: qsTr("Connected")
                    }

                    ToolButton {
                        id: compactWifiDetails
                        visible: root.compactMenu && networkRow.isCurrent
                        implicitWidth: 28
                        implicitHeight: 28
                        Accessible.name: (networkRow.showingDetails ? qsTr("Hide details for %1")
                            : qsTr("Show details for %1")).arg(networkRow.network.name || qsTr("Wi-Fi network"))
                        Accessible.expandable: true
                        Accessible.expanded: networkRow.showingDetails
                        onClicked: root.toggleDetails(networkRow.network)
                        Keys.onReturnPressed: compactWifiDetails.clicked()
                        Keys.onEnterPressed: compactWifiDetails.clicked()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        contentItem: Text {
                            text: networkRow.showingDetails ? "−" : "⋯"
                            color: compactWifiDetails.hovered ? Tokens.menuAccent : Tokens.menuMuted
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 7
                            color: compactWifiDetails.hovered ? Tokens.menuHover : "transparent"
                            border.width: compactWifiDetails.visualFocus ? 2 : 0
                            border.color: Tokens.menuAccent
                        }
                    }

                    RoundedButton {
                        id: connectBtn
                        visible: !root.compactMenu
                        Layout.minimumWidth: 68
                        implicitHeight: root.settingsPage ? 34 : 28
                        text: networkRow.isCurrent ? "Disconnect"
                            : (networkRow.ownOperation
                                ? (root.pendingAction === "cancel" ? "Cancelling…" : "Cancel")
                                : (root.operationPending ? "Wait" : "Connect"))
                        enabled: Networking.wifiEnabled && Networking.wifiHardwareEnabled
                            && !root.hotspotBlocksSelectedWifi
                            && (!root.operationPending || networkRow.ownOperation)
                            && (!networkRow.ownOperation || root.pendingAction === "connect")
                        Accessible.name: networkRow.isCurrent
                            ? "Disconnect from " + (networkRow.network.name || "network")
                            : (networkRow.ownOperation ? "Cancel connection to "
                                + (networkRow.network.name || "network")
                                : "Connect to " + (networkRow.network.name || "network"))
                        onClicked: {
                            if (networkRow.isCurrent) root.disconnectNetwork(networkRow.network);
                            else if (networkRow.ownOperation) root.cancelConnection(networkRow.network);
                            else root.connectNetwork(networkRow.network, false);
                        }
                        contentItem: Text {
                            text: connectBtn.text
                            font.pixelSize: root.settingsPage ? 13 : 11
                            font.weight: Font.Medium
                            color: !connectBtn.enabled ? Tokens.text_secondary
                                : root.settingsPage ? Tokens.text_primary
                                : (networkRow.isCurrent ? Qt.rgba(0.95, 0.45, 0.47, 1.0) : (connectBtn.down ? Tokens.text_primary : Tokens.accent))
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: root.settingsPage ? 8 : 14
                            color: root.settingsPage ? (connectBtn.hovered ? Tokens.surface_high : Tokens.surface)
                                : !connectBtn.enabled ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.2)
                                : (networkRow.isCurrent
                                    ? (connectBtn.hovered ? Qt.rgba(0.92, 0.38, 0.4, 0.22) : Qt.rgba(0.92, 0.38, 0.4, 0.12))
                                    : (connectBtn.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.24) : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.10)))
                            border.color: root.settingsPage ? (connectBtn.visualFocus ? Tokens.focus_ring : Tokens.outline)
                                : !connectBtn.enabled ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2)
                                : (networkRow.isCurrent
                                    ? Qt.rgba(0.92, 0.38, 0.4, 0.45)
                                    : (connectBtn.hovered ? Tokens.accent : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.38)))
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }

                    ToolButton {
                        id: rowMoreBtn
                        visible: !root.compactMenu
                        implicitWidth: 28
                        implicitHeight: 28
                        text: "⋯"
                        Accessible.name: "More actions for " + (networkRow.network.name || "network")
                        onClicked: rowMenu.requestOpen()
                        contentItem: Text {
                            text: "⋯"
                            font.pixelSize: 12
                            color: rowMoreBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 14
                            color: rowMoreBtn.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.6) : "transparent"
                            border.color: rowMoreBtn.hovered ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3) : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        ActionMenu {
                            id: rowMenu

                            ActionMenuItem {
                                text: networkRow.showingDetails ? "Hide details" : "Details"
                                onTriggered: root.toggleDetails(networkRow.network)
                            }

                            ActionMenuItem {
                                text: "Forget saved profiles…"
                                visible: networkRow.network.known
                                enabled: !root.hotspotBlocksSelectedWifi
                                    && !root.operationPending && !root.pendingForgetNetwork
                                onTriggered: root.requestForget(networkRow.network)
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: networkRow.showingDetails
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: "Adapter: " + (networkRow.network.device
                            ? networkRow.network.device.name : "Unavailable")
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                        textFormat: Text.PlainText
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Signal " + root.signalPercent(networkRow.network) + "% · "
                            + root.securityLabel(networkRow.network)
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                        textFormat: Text.PlainText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: networkRow.passwordPrompt
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        TextField {
                            id: passwordField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 90
                            implicitHeight: 34
                            placeholderText: "Wi-Fi password"
                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                            text: root.passwordText
                            Accessible.name: "Password for " + (networkRow.network.name || "network")
                            onTextChanged: root.passwordText = text
                            onAccepted: root.connectNetwork(networkRow.network, true)
                            onVisibleChanged: {
                                if (visible) forceActiveFocus();
                            }
                            background: Rectangle {
                                radius: 14
                                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.8)
                                border.color: passwordField.activeFocus ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                                border.width: passwordField.activeFocus ? 2 : 1
                            }
                            color: Tokens.text_primary
                            selectionColor: Tokens.accent
                        }

                        ToolButton {
                            id: showPassBtn
                            implicitWidth: 50
                            implicitHeight: 34
                            text: root.showPassword ? "Hide" : "Show"
                            Accessible.name: root.showPassword ? "Hide password" : "Show password"
                            onClicked: root.showPassword = !root.showPassword
                            contentItem: Text {
                                text: showPassBtn.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: showPassBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 14
                                color: showPassBtn.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.35)
                                border.color: showPassBtn.hovered ? Tokens.outline : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                                border.width: 1
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }

                        RoundedButton {
                            id: cancelPassBtn
                            text: "Cancel"
                            implicitHeight: 28
                            implicitWidth: 64
                            enabled: !root.operationPending
                            onClicked: root.cancelPassword()
                            contentItem: Text {
                                text: cancelPassBtn.text
                                font.pixelSize: 11
                                color: cancelPassBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 14
                                color: cancelPassBtn.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.6) : "transparent"
                                border.color: cancelPassBtn.hovered ? Tokens.outline : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                                border.width: 1
                            }
                        }

                        RoundedButton {
                            id: submitPassBtn
                            text: "Connect"
                            implicitHeight: 28
                            implicitWidth: 72
                            enabled: root.passwordText.length > 0 && !root.operationPending
                                && !root.hotspotBlocksSelectedWifi
                            onClicked: root.connectNetwork(networkRow.network, true)
                            contentItem: Text {
                                text: submitPassBtn.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: submitPassBtn.enabled ? Tokens.on_accent : Tokens.text_secondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 14
                                color: submitPassBtn.enabled ? (submitPassBtn.hovered ? Qt.darker(Tokens.accent, 1.1) : Tokens.accent) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.2)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: networkRow.confirmingForget
                    spacing: 7

                    Text {
                        Layout.fillWidth: true
                        text: "Remove all saved profiles for this network?"
                        font.pixelSize: 10
                        color: Tokens.text_secondary
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }

                    RoundedButton {
                        id: cancelForgetBtn
                        text: "Cancel"
                        implicitHeight: 28
                        implicitWidth: 64
                        onClicked: root.forgetConfirmationNetwork = null
                        contentItem: Text {
                            text: cancelForgetBtn.text
                            font.pixelSize: 11
                            color: cancelForgetBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 14
                            color: cancelForgetBtn.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.6) : "transparent"
                            border.color: cancelForgetBtn.hovered ? Tokens.outline : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                            border.width: 1
                        }
                    }

                    RoundedButton {
                        id: confirmForgetBtn
                        text: "Forget"
                        implicitHeight: 28
                        implicitWidth: 64
                        enabled: !root.operationPending && !root.hotspotBlocksSelectedWifi
                        onClicked: root.forgetNetwork(networkRow.network)
                        contentItem: Text {
                            text: confirmForgetBtn.text
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: confirmForgetBtn.enabled ? Qt.rgba(0.95, 0.45, 0.47, 1.0) : Tokens.text_secondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 14
                            color: confirmForgetBtn.enabled
                                ? (confirmForgetBtn.hovered ? Qt.rgba(0.82, 0.25, 0.27, 0.28) : Qt.rgba(0.82, 0.25, 0.27, 0.16))
                                : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.2)
                            border.color: confirmForgetBtn.enabled ? Qt.rgba(0.92, 0.38, 0.4, 0.75) : Tokens.outline
                            border.width: 1
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.pendingForgetNetwork === networkRow.network
                    text: "Removing saved profiles…"
                    font.pixelSize: 10
                    color: Tokens.text_secondary
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
