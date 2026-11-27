pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../theme"
import "../services"

PanelWindow {
    id: barRoot

    required property ShellScreen targetScreen
    required property ShellPresentation presentation
    property bool connectivityMenuOpen: false
    screen: targetScreen
    color: "transparent"
    implicitHeight: 40

    signal requestLauncher()
    signal requestDashboard(string tab)
    signal requestSideDrawer(string type)
    signal requestConnectivityMenu(string type, Item anchorItem)

    anchors {
        top: true
        left: true
        right: true
    }

    exclusiveZone: 40
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property bool wifiEnabled: Networking.wifiEnabled && Networking.wifiHardwareEnabled
    readonly property bool wifiConnected: Networking.devices.values.some(
        device => device.type === DeviceType.Wifi && device.connected)
    readonly property string wifiStatusText: !Networking.wifiHardwareEnabled ? "Unavailable"
        : !Networking.wifiEnabled ? "Off" : wifiConnected ? "Connected" : "On"
    readonly property color wifiStatusColor: !wifiEnabled ? Tokens.danger
        : wifiConnected ? Tokens.accent : Tokens.text_secondary
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothEnabled: !!bluetoothAdapter && bluetoothAdapter.enabled
    readonly property bool bluetoothConnected: bluetoothEnabled
        && bluetoothAdapter.devices.values.some(device => device.connected)
    readonly property string bluetoothStatusText: !bluetoothAdapter ? "Unavailable"
        : !bluetoothEnabled ? "Off" : bluetoothConnected ? "Connected" : "On"
    readonly property color bluetoothStatusColor: !bluetoothEnabled ? Tokens.danger
        : bluetoothConnected ? Tokens.accent : Tokens.text_secondary

    Component.onCompleted: {
        if (Networking.canCheckConnectivity) Networking.checkConnectivity();
    }

    // 1. Left Floating Island: App Launcher & Workspaces
    Rectangle {
        id: leftIsland
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        implicitWidth: leftLayout.implicitWidth + 20
        radius: 12
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        RowLayout {
            id: leftLayout
            anchors.centerIn: parent
            spacing: 8

            // App Launcher Icon Button
            Rectangle {
                width: 24
                height: 24
                radius: 6
                color: launcherHover.hovered ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰣇"
                    font.pixelSize: 14
                    color: Tokens.accent
                }

                HoverHandler { id: launcherHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestLauncher()
                }
            }

            // Divider line
            Rectangle {
                width: 1
                height: 14
                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
            }

            // Workspaces Module
            Workspaces {
                Layout.alignment: Qt.AlignVCenter
                targetMonitor: Hyprland.monitorFor(barRoot.targetScreen)
                workspaceList: Hyprland.workspaces.values
            }
        }
    }

    // 2. Right Floating Island: Status Tray & Clock Pill
    Rectangle {
        id: rightIsland
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        implicitWidth: rightLayout.implicitWidth + 20
        radius: 12
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.barOpacity)
        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        RowLayout {
            id: rightLayout
            anchors.centerIn: parent
            spacing: 8

            // Status Tray
            StatusTray {
                objectName: "bar-system-tray"
                visible: barRoot.presentation.showTray
                Layout.alignment: Qt.AlignVCenter
                parentWindow: barRoot
            }

            // Internet connectivity
            Rectangle {
                id: internetPill
                objectName: "bar-connectivity"
                Layout.alignment: Qt.AlignVCenter
                height: 24
                implicitWidth: internetContent.implicitWidth + 16
                radius: height / 2
                color: internetHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                border.width: 1
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                Behavior on color { ColorAnimation { duration: 150 } }

                Accessible.role: Accessible.Button
                Accessible.name: "Wi-Fi · " + barRoot.wifiStatusText
                Accessible.onPressAction: barRoot.requestConnectivityMenu("wifi", internetPill)

                Row {
                    id: internetContent
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.pixelSize: 13
                        color: barRoot.wifiStatusColor
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: width
                        radius: width / 2
                        color: barRoot.wifiStatusColor
                    }
                }

                HoverHandler { id: internetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestConnectivityMenu("wifi", internetPill)
                }
                activeFocusOnTab: true
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        barRoot.requestConnectivityMenu("wifi", internetPill);
                        event.accepted = true;
                    }
                }

                PopupWindow {
                    anchor.item: internetPill
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                    visible: internetPill.visible && internetHover.hovered && !barRoot.connectivityMenuOpen
                    implicitWidth: internetTooltip.implicitWidth + 16
                    implicitHeight: 26
                    color: "transparent"

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Tokens.surface_high
                        border.color: Tokens.outline

                        Text {
                            id: internetTooltip
                            anchors.centerIn: parent
                            text: internetPill.Accessible.name
                            font.pixelSize: 11
                            color: Tokens.text_primary
                        }
                    }
                }
            }

            Rectangle {
                id: bluetoothPill
                objectName: "bar-bluetooth"
                Layout.alignment: Qt.AlignVCenter
                height: 24
                width: 32
                radius: height / 2
                color: bluetoothHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                border.width: 1
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                Accessible.role: Accessible.Button
                Accessible.name: "Bluetooth · " + barRoot.bluetoothStatusText
                Accessible.onPressAction: barRoot.requestConnectivityMenu("bluetooth", bluetoothPill)

                Text {
                    anchors.centerIn: parent
                    text: "󰂯"
                    font.pixelSize: 14
                    color: barRoot.bluetoothStatusColor
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 3
                    anchors.bottomMargin: 3
                    width: 5
                    height: width
                    radius: width / 2
                    color: barRoot.bluetoothStatusColor
                }
                HoverHandler { id: bluetoothHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestConnectivityMenu("bluetooth", bluetoothPill)
                }
                activeFocusOnTab: true
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        barRoot.requestConnectivityMenu("bluetooth", bluetoothPill);
                        event.accepted = true;
                    }
                }

                PopupWindow {
                    anchor.item: bluetoothPill
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                    visible: bluetoothHover.hovered && !barRoot.connectivityMenuOpen
                    implicitWidth: bluetoothTooltip.implicitWidth + 16
                    implicitHeight: 26
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Tokens.surface_high
                        border.color: Tokens.outline
                        Text {
                            id: bluetoothTooltip
                            anchors.centerIn: parent
                            text: bluetoothPill.Accessible.name
                            font.pixelSize: 11
                            color: Tokens.text_primary
                        }
                    }
                }
            }

            RowLayout {
                objectName: "bar-battery"
                visible: barRoot.presentation.showBattery && UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Text {
                    text: UPower.displayDevice.state === UPowerDeviceState.Charging ? "󰂄" : "󰁹"
                    font.pixelSize: 14
                    color: Tokens.accent
                }
                Text {
                    text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                        + (UPower.displayDevice.state === UPowerDeviceState.Charging ? " ⚡" : "")
                    font.pixelSize: 10
                    font.bold: true
                    color: Tokens.text_primary
                }
            }

            // Divider between network status and clock
            Rectangle {
                visible: barRoot.presentation.showTray || barRoot.presentation.showConnectivity
                    || (barRoot.presentation.showBattery && UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery)
                width: 1
                height: 14
                color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
            }

            // Clock Pill
            Rectangle {
                id: clockPill
                height: 24
                implicitWidth: clockContent.implicitWidth + 14
                radius: 8
                color: clockHover.hovered
                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25)
                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.7)
                Behavior on color { ColorAnimation { duration: 150 } }

                SystemClock {
                    id: minuteClock
                    precision: barRoot.presentation.showClockSeconds ? SystemClock.Seconds : SystemClock.Minutes
                }

                RowLayout {
                    id: clockContent
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: "󰥔"
                        font.pixelSize: 11
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_secondary
                    }

                    Text {
                        id: clockText
                        objectName: "bar-clock-text"
                        text: Qt.formatDateTime(minuteClock.date, barRoot.presentation.showClockSeconds ? "hh:mm:ss" : "hh:mm")
                        font.pixelSize: 12
                        font.bold: true
                        color: clockHover.hovered ? Tokens.accent : Tokens.text_primary
                    }
                }

                HoverHandler { id: clockHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: barRoot.requestDashboard("")
                }

            }
        }
    }
}
