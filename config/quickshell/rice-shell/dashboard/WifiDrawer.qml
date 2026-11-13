pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
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

    readonly property var wifiDevice: {
        var devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i];
            if (device.type === DeviceType.Wifi) return device;
        }
        return null;
    }
    readonly property var networks: {
        if (!wifiDevice) return [];
        var list = wifiDevice.networks.values.slice();
        list.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return list;
    }
    property var selectedNetwork: null
    property var pendingNetwork: null
    property string pendingAction: ""
    property string passwordText: ""
    property string statusMessage: ""
    property bool isConnecting: false
    property var scanOwnedDevice: null
    property bool isScanning: wifiDevice ? wifiDevice.scannerEnabled : false
    property bool scanRequested: true

    Binding {
        target: root.scanOwnedDevice
        property: "scannerEnabled"
        value: root.visible && root.scanRequested
        when: root.scanOwnedDevice !== null
    }

    onWifiDeviceChanged: {
        if (scanOwnedDevice && scanOwnedDevice !== wifiDevice) {
            stopScan();
        }
        if (!wifiDevice) {
            if (isConnecting) {
                isConnecting = false;
                pendingNetwork = null;
                pendingAction = "";
            }
            statusMessage = "Wi-Fi adapter unavailable";
            selectedNetwork = null;
            passwordText = "";
            scanRestartTimer.stop();
        } else if (visible) {
            startScan();
        }
    }

    onVisibleChanged: {
        if (visible) {
            startScan();
        } else {
            stopScan();
            if (!root.isConnecting) {
                root.selectedNetwork = null;
            }
            root.passwordText = "";
        }
    }

    Component.onDestruction: {
        stopScan();
        root.selectedNetwork = null;
        root.passwordText = "";
    }

    function cancelPassword(): void {
        root.selectedNetwork = null;
        root.passwordText = "";
    }

    function startScan(): void {
        root.statusMessage = root.wifiDevice ? "" : "Wi-Fi adapter unavailable";
        if (!root.wifiDevice) return;
        if (!root.wifiDevice.scannerEnabled) {
            root.scanOwnedDevice = root.wifiDevice;
        }
        root.scanRequested = true;
    }

    function stopScan(): void {
        var owned = root.scanOwnedDevice;
        root.scanOwnedDevice = null;
        if (owned && owned.scannerEnabled) {
            owned.scannerEnabled = false;
        }
    }

    function scan(): void {
        root.statusMessage = root.wifiDevice ? "" : "Wi-Fi adapter unavailable";
        if (!root.wifiDevice) return;
        if (!root.wifiDevice.scannerEnabled) {
            root.scanOwnedDevice = root.wifiDevice;
        }
        root.scanRequested = false;
        scanRestartTimer.restart();
    }

    Timer {
        id: scanRestartTimer
        interval: 180
        onTriggered: root.scanRequested = true
    }

    Timer {
        id: actionTimeout
        interval: 30000
        repeat: false
        running: root.isConnecting
        onTriggered: {
            root.isConnecting = false;
            root.pendingNetwork = null;
            root.pendingAction = "";
            root.statusMessage = "Connection timed out";
            root.passwordText = "";
        }
    }

    Connections {
        target: root.pendingNetwork
        ignoreUnknownSignals: true

        function onConnectedChanged(): void {
            if (!root.pendingNetwork) return;

            if (root.pendingNetwork.connected) {
                root.isConnecting = false;
                root.statusMessage = "Connected to " + root.pendingNetwork.name;
                root.selectedNetwork = null;
                root.passwordText = "";
                root.pendingNetwork = null;
                root.pendingAction = "";
            } else if (root.pendingAction === "disconnect") {
                root.isConnecting = false;
                root.statusMessage = "Disconnected from " + root.pendingNetwork.name;
                root.pendingNetwork = null;
                root.pendingAction = "";
            }
        }

        function onStateChangingChanged(): void {
            if (!root.pendingNetwork) return;
            if (!root.pendingNetwork.stateChanging) {
                if (root.pendingNetwork.connected) {
                    root.isConnecting = false;
                    root.statusMessage = "Connected to " + root.pendingNetwork.name;
                    root.selectedNetwork = null;
                    root.passwordText = "";
                    root.pendingNetwork = null;
                    root.pendingAction = "";
                } else if (root.pendingAction === "disconnect") {
                    root.isConnecting = false;
                    root.statusMessage = "Disconnected from " + root.pendingNetwork.name;
                    root.pendingNetwork = null;
                    root.pendingAction = "";
                } else if (root.pendingAction === "connect") {
                    root.isConnecting = false;
                    root.statusMessage = "Could not connect to " + root.pendingNetwork.name;
                    root.passwordText = "";
                    root.pendingNetwork = null;
                    root.pendingAction = "";
                }
            }
        }

        function onConnectionFailed(reason): void {
            if (!root.pendingNetwork) return;

            root.isConnecting = false;
            root.passwordText = "";
            if (reason === ConnectionFailReason.NoSecrets && root.supportsPsk(root.pendingNetwork)) {
                root.selectedNetwork = root.pendingNetwork;
                root.statusMessage = "Incorrect password or authentication required";
            } else if (reason === ConnectionFailReason.NoSecrets) {
                root.statusMessage = "This network needs a saved NetworkManager profile";
            } else if (reason === ConnectionFailReason.WifiAuthTimeout) {
                root.statusMessage = "Wi-Fi authentication timed out";
            } else if (reason === ConnectionFailReason.WifiNetworkLost) {
                root.statusMessage = "Wi-Fi network disappeared";
            } else {
                root.statusMessage = "Could not connect to " + root.pendingNetwork.name;
            }
            root.pendingNetwork = null;
            root.pendingAction = "";
        }
    }

    function supportsPsk(net): bool {
        return net.security === WifiSecurityType.WpaPsk
            || net.security === WifiSecurityType.Wpa2Psk
            || net.security === WifiSecurityType.Sae;
    }

    function requiresPassword(net): bool {
        return !net.known && root.supportsPsk(net);
    }

    function connectNetwork(net, withPassword): void {
        if (!net) return;

        if (root.isConnecting) {
            if (root.pendingNetwork === net) {
                if (typeof net.disconnect === "function") net.disconnect();
                root.isConnecting = false;
                root.pendingNetwork = null;
                root.pendingAction = "";
                root.statusMessage = "Connection cancelled";
                root.passwordText = "";
            }
            return;
        }

        if (net.stateChanging) {
            root.pendingNetwork = net;
            root.pendingAction = net.state === ConnectionState.Connecting ? "connect" : "disconnect";
            root.isConnecting = true;
            root.statusMessage = net.state === ConnectionState.Connecting
                ? "Connecting to " + net.name + "..."
                : "Disconnecting from " + net.name + "...";
            return;
        }

        if (net.connected) {
            root.pendingNetwork = net;
            root.pendingAction = "disconnect";
            root.isConnecting = true;
            root.statusMessage = "Disconnecting from " + net.name + "...";
            net.disconnect();
            return;
        }

        if (root.requiresPassword(net) && !withPassword) {
            root.selectedNetwork = net;
            root.passwordText = "";
            root.statusMessage = "";
            return;
        }

        if (!withPassword && root.selectedNetwork !== net) {
            root.selectedNetwork = null;
            root.passwordText = "";
        }

        if (withPassword && root.passwordText.length === 0) {
            root.statusMessage = "Enter a password";
            return;
        }

        root.pendingNetwork = net;
        root.pendingAction = "connect";
        root.isConnecting = true;
        root.statusMessage = "Connecting to " + net.name + "...";
        if (withPassword) {
            net.connectWithPsk(root.passwordText);
        } else {
            net.connect();
        }
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
                TapHandler { onTapped: { root.cancelPassword(); root.closeRequested(); } }
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
            visible: !Networking.wifiEnabled || root.networks.length === 0

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
                    text: !root.wifiDevice
                        ? "Wi-Fi adapter unavailable"
                        : (!Networking.wifiEnabled
                            ? "Wi-Fi is disabled"
                            : (root.isScanning ? "Scanning for networks..." : "No Wi-Fi networks found"))
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
            visible: Networking.wifiEnabled && root.networks.length > 0
            clip: true
            spacing: 6
            model: root.networks

            delegate: Rectangle {
                id: netRow
                required property var modelData
                width: netListView.width
                height: isSelectedPasswordRow ? 74 : 36
                radius: 8
                color: modelData.connected
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : (rowHover.hovered ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.5))
                border.color: modelData.connected
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.5)
                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.2)
                border.width: 1

                readonly property bool isSelectedPasswordRow: root.selectedNetwork === modelData && !modelData.connected

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
                                var s = netRow.modelData.signalStrength * 100;
                                if (s >= 75) return "󰤨";
                                if (s >= 50) return "󰤥";
                                if (s >= 25) return "󰤢";
                                return "󰤟";
                            }
                            font.pixelSize: 13
                            color: netRow.modelData.connected ? Tokens.accent : Tokens.text_secondary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: netRow.modelData.name
                            font.pixelSize: 11
                            font.bold: netRow.modelData.connected
                            color: Tokens.text_primary
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: netRow.modelData.connected
                            text: "Connected"
                            font.pixelSize: 9
                            color: Tokens.accent
                        }

                        Text {
                            visible: netRow.modelData.security !== WifiSecurityType.Open
                                && netRow.modelData.security !== WifiSecurityType.Unknown
                            text: "󰌾"
                            font.pixelSize: 10
                            color: Tokens.text_secondary
                        }

                        Text {
                            visible: netRow.modelData.connected
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
                                onAccepted: root.connectNetwork(netRow.modelData, true)
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
                                text: root.isConnecting ? "..." : "Connect"
                                font.pixelSize: 10
                                font.bold: true
                                color: Tokens.surface
                            }

                            HoverHandler { id: connectHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                enabled: !root.isConnecting && root.passwordText.length > 0
                                onTapped: root.connectNetwork(netRow.modelData, true)
                            }
                        }
                    }
                }

                TapHandler {
                    // Only trigger if not clicking inside password field
                    enabled: !netRow.isSelectedPasswordRow && !root.isConnecting
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
