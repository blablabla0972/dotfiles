pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Networking
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 276
    implicitHeight: 420
    radius: 24
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.72)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.24)
    border.width: 1

    readonly property var wifiDevice: {
        var devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        }
        return null;
    }
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiCanToggle: wifiDevice !== null && Networking.wifiHardwareEnabled
        && !Hotspot.active
    readonly property bool btEnabled: btAdapter ? btAdapter.enabled : false
    readonly property string wifiSublabel: {
        if (!wifiDevice) return qsTr("Unavailable");
        if (!Networking.wifiHardwareEnabled) return qsTr("Hardware blocked");
        if (!Networking.wifiEnabled) return qsTr("Off");
        if (Hotspot.active) return qsTr("Used by Hotspot");
        var networks = wifiDevice.networks.values;
        for (var i = 0; i < networks.length; i++) {
            if (networks[i].connected) return networks[i].name || qsTr("Connected");
        }
        return qsTr("Not connected");
    }
    readonly property string btSublabel: {
        if (!btAdapter) return qsTr("Adapter unavailable");
        if (!btAdapter.enabled) return qsTr("Off");
        var devices = btAdapter.devices.values;
        var connected = [];
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].connected) connected.push(devices[i].name || "");
        }
        if (connected.length === 1) return connected[0] || qsTr("1 device connected");
        if (connected.length > 1) return qsTr("%1 devices connected").arg(connected.length);
        return qsTr("No devices connected");
    }

    property bool wifiPending: false
    property bool expectedWifiState: false
    property bool bluetoothPending: false
    property bool expectedBluetoothState: false
    property string wifiError: ""
    property string bluetoothError: ""
    property string sharedError: ""

    signal requestSideDrawer(string type)

    function setBrightness(value: real): void {
        DesktopControls.setBrightness(value);
    }

    function toggleWifi(): void {
        if (!wifiCanToggle || wifiPending) return;
        expectedWifiState = !Networking.wifiEnabled;
        wifiPending = true;
        wifiTimeout.restart();
        Networking.wifiEnabled = expectedWifiState;
    }

    function toggleBluetooth(): void {
        if (!btAdapter || bluetoothPending) return;
        expectedBluetoothState = !btAdapter.enabled;
        bluetoothPending = true;
        bluetoothTimeout.restart();
        btAdapter.enabled = expectedBluetoothState;
    }

    Timer {
        id: wifiTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.wifiPending) return;
            root.wifiPending = false;
            root.wifiError = qsTr("Wi-Fi state not confirmed");
            wifiErrorTimeout.restart();
        }
    }

    Timer {
        id: bluetoothTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.bluetoothPending) return;
            root.bluetoothPending = false;
            root.bluetoothError = qsTr("Bluetooth state not confirmed");
            bluetoothErrorTimeout.restart();
        }
    }

    Timer {
        id: wifiErrorTimeout
        interval: 4000
        repeat: false
        onTriggered: root.wifiError = ""
    }

    Timer {
        id: bluetoothErrorTimeout
        interval: 4000
        repeat: false
        onTriggered: root.bluetoothError = ""
    }

    Timer {
        id: sharedErrorTimeout
        interval: 5000
        repeat: false
        onTriggered: root.sharedError = ""
    }

    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        onTriggered: DesktopControls.refreshBrightness(false)
    }

    readonly property bool wifiServiceEnabled: (typeof Networking !== "undefined") ? Networking.wifiEnabled : false
    readonly property bool wifiServiceHardwareEnabled: (typeof Networking !== "undefined") ? Networking.wifiHardwareEnabled : false
    onWifiServiceEnabledChanged: {
        if (root.wifiPending && root.wifiServiceEnabled === root.expectedWifiState) {
            root.wifiPending = false;
            wifiTimeout.stop();
            root.wifiError = "";
        }
    }
    onWifiServiceHardwareEnabledChanged: {
        if (!root.wifiServiceHardwareEnabled && root.wifiPending) {
            root.wifiPending = false;
            wifiTimeout.stop();
            root.wifiError = qsTr("Wi-Fi hardware is blocked");
            wifiErrorTimeout.restart();
        }
    }

    Connections {
        target: root.btAdapter
        function onEnabledChanged() {
            if (root.bluetoothPending && root.btAdapter
                    && root.btAdapter.enabled === root.expectedBluetoothState) {
                root.bluetoothPending = false;
                bluetoothTimeout.stop();
                root.bluetoothError = "";
            }
        }
    }

    Connections {
        target: DesktopControls
        function onErrorOccurred(message) {
            root.sharedError = message;
            sharedErrorTimeout.restart();
        }
    }

    Component.onCompleted: DesktopControls.refreshBrightness(false)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22

            Text {
                text: qsTr("Quick Settings")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Tokens.text_primary
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.sharedError.length ? "!" : ""
                font.pixelSize: 12
                color: Tokens.danger
                Accessible.name: root.sharedError
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            QuickSettingSlider {
                Layout.fillWidth: true
                icon: Audio.muted ? "󰝟" : "󰕾"
                label: qsTr("Volume")
                value: Audio.volume
                maximum: 1.5
                step: 0.05
                device: Audio.sink
                available: Audio.available
                valueText: !Audio.available ? qsTr("Unavailable")
                    : (Audio.muted ? qsTr("Muted") : Math.round(Audio.volume * 100) + "%")
                        + (Audio.available && !Audio.muted && Audio.volume > 1 ? qsTr(" · Boost") : "")
                onValueRequested: (value) => Audio.setVolume(value)
            }

            QuickSettingSlider {
                Layout.fillWidth: true
                icon: "󰃠"
                label: qsTr("Brightness")
                value: DesktopControls.brightnessLevel
                maximum: 1
                step: 0.05
                available: DesktopControls.brightnessAvailable
                valueText: DesktopControls.brightnessAvailable
                    ? Math.round(DesktopControls.brightnessLevel * 100) + "%"
                    : (DesktopControls.brightnessError || qsTr("Unavailable"))
                onValueRequested: (value) => root.setBrightness(value)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: tileFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: tileGrid.implicitHeight + 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                GridLayout {
                    id: tileGrid
                    width: tileFlickable.width
                    columns: 2
                    rowSpacing: 6
                    columnSpacing: 6

                    QuickSettingTile {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        icon: "󰤨"
                        label: qsTr("Wi-Fi")
                        sublabel: root.wifiError || root.wifiSublabel
                        active: root.wifiEnabled
                        available: root.wifiCanToggle
                        pending: root.wifiPending
                        hasDetails: true
                        onActivated: root.toggleWifi()
                        onDetailsRequested: root.requestSideDrawer("wifi")
                    }

                    QuickSettingTile {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        icon: "󰂯"
                        label: qsTr("Bluetooth")
                        sublabel: root.bluetoothError || root.btSublabel
                        active: root.btEnabled
                        available: root.btAdapter !== null
                        pending: root.bluetoothPending
                        hasDetails: true
                        onActivated: root.toggleBluetooth()
                        onDetailsRequested: root.requestSideDrawer("bluetooth")
                    }

                    QuickSettingTile {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        icon: "󰀃"
                        label: qsTr("Hotspot")
                        sublabel: Hotspot.tileStatus
                        active: Hotspot.active
                        available: Hotspot.available
                        pending: Hotspot.busy
                        hasDetails: true
                        onActivated: {
                            if (Hotspot.active) {
                                Hotspot.toggle();
                            } else if (Hotspot.clientConflict || !Hotspot.canStart) {
                                root.requestSideDrawer("hotspot");
                            } else {
                                Hotspot.toggle();
                            }
                        }
                        onDetailsRequested: root.requestSideDrawer("hotspot")
                    }

                    QuickSettingTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        icon: Audio.muted ? "󰝟" : "󰕾"
                        label: qsTr("Sound")
                        sublabel: !Audio.available ? qsTr("Unavailable")
                            : Audio.muted ? qsTr("Muted") : qsTr("On")
                        active: Audio.muted
                        available: Audio.available
                        hasDetails: true
                        onActivated: Audio.toggleMute()
                        onDetailsRequested: root.requestSideDrawer("audio")
                    }

                    QuickSettingTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        icon: "󰂛"
                        label: qsTr("Do Not Disturb")
                        sublabel: DesktopControls.doNotDisturb ? qsTr("On") : qsTr("Off")
                        active: DesktopControls.doNotDisturb
                        onActivated: DesktopControls.doNotDisturb = !DesktopControls.doNotDisturb
                    }

                    QuickSettingTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        icon: "󰖔"
                        label: qsTr("Night Light")
                        sublabel: DesktopControls.nightLightActive ? qsTr("On") : qsTr("Off")
                        active: DesktopControls.nightLightActive
                        onActivated: DesktopControls.toggleNightLight()
                    }

                    QuickSettingTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        icon: "󰅶"
                        label: qsTr("Awake")
                        sublabel: DesktopControls.caffeineActive ? qsTr("Preventing idle") : qsTr("Off")
                        active: DesktopControls.caffeineActive
                        onActivated: DesktopControls.toggleCaffeine()
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 14 : 0
            visible: root.sharedError.length > 0
            text: root.sharedError
            font.pixelSize: 10
            color: Tokens.danger
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
}
