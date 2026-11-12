pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 220
    implicitHeight: 310
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    property bool wifiActive: true
    property bool btActive: true
    property bool dndActive: false
    property bool nightLightActive: false
    property bool caffeineActive: false
    property real brightness: 0.8

    property bool wifiDrawerOpen: false
    property bool btDrawerOpen: false

    Process {
        id: wifiToggleProcess
    }

    Process {
        id: btToggleProcess
    }

    Process {
        id: readBrightProcess
        command: ["brightnessctl", "get", "-m"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parts = text.trim().split(",");
                    if (parts.length >= 4) {
                        var pctStr = parts[3].replace("%", "").trim();
                        var val = parseInt(pctStr);
                        if (!isNaN(val)) root.brightness = Math.max(0.05, Math.min(1.0, val / 100.0));
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: setBrightProcess
    }

    function setBrightness(val: real): void {
        var clamped = Math.max(0.05, Math.min(1.0, val));
        root.brightness = clamped;
        setBrightProcess.command = ["brightnessctl", "set", Math.round(clamped * 100) + "%"];
        setBrightProcess.running = true;
    }

    Component.onCompleted: {
        readBrightProcess.running = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Section Title with subtle badge
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Quick Controls"
                font.pixelSize: 13
                font.bold: true
                color: Tokens.text_primary
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Settings"
                font.pixelSize: 10
                color: Tokens.text_secondary
            }
        }

        // 1. Integrated Volume Slider Row
        Rectangle {
            id: volTrack
            Layout.fillWidth: true
            height: 36
            radius: 10
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.85)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1
            clip: true

            // Active volume fill
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.min(parent.width, Math.max(0, parent.width * Audio.volume))
                color: Audio.muted ? Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.4) : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.22)
            }

            // Foreground content
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10

                Text {
                    text: Audio.muted ? "󰝟" : (Audio.volume > 0.5 ? "󰕾" : (Audio.volume > 0.05 ? "󰖀" : "󰕿"))
                    font.pixelSize: 15
                    color: Audio.muted ? Tokens.danger : Tokens.accent
                }

                Text {
                    text: "Volume"
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_primary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_secondary
                }
            }

            // Continuous Drag & Click Handler
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateVolume(mouse) {
                    var ratio = Math.max(0.0, Math.min(1.0, mouse.x / volTrack.width));
                    Audio.setVolume(ratio);
                }
                onPressed: (mouse) => updateVolume(mouse)
                onPositionChanged: (mouse) => {
                    if (pressed) updateVolume(mouse);
                }
            }
        }

        // 2. Integrated Brightness Slider Row
        Rectangle {
            id: brightTrack
            Layout.fillWidth: true
            height: 36
            radius: 10
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.85)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
            border.width: 1
            clip: true

            // Active brightness fill
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.min(parent.width, Math.max(0, parent.width * root.brightness))
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.22)
            }

            // Foreground content
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10

                Text {
                    text: "󰃠"
                    font.pixelSize: 15
                    color: Tokens.accent
                }

                Text {
                    text: "Brightness"
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_primary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Math.round(root.brightness * 100) + "%"
                    font.pixelSize: 11
                    font.bold: true
                    color: Tokens.text_secondary
                }
            }

            // Continuous Drag & Click Handler
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateBrightness(mouse) {
                    var ratio = Math.max(0.05, Math.min(1.0, mouse.x / brightTrack.width));
                    root.setBrightness(ratio);
                }
                onPressed: (mouse) => updateBrightness(mouse)
                onPositionChanged: (mouse) => {
                    if (pressed) updateBrightness(mouse);
                }
            }
        }

        // 3. Compact 2-Column Quick Toggle Tiles (fills remaining height evenly without gaps)
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            // Wi-Fi
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.wifiActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.wifiActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰤨"; font.pixelSize: 15; color: root.wifiActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Wi-Fi"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                    Text { text: "󰅂"; font.pixelSize: 11; color: Tokens.text_secondary }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (eventPoint) => {
                        if (eventPoint.event.button === Qt.RightButton) {
                            root.wifiDrawerOpen = true;
                        } else {
                            root.wifiActive = !root.wifiActive;
                            wifiToggleProcess.command = ["nmcli", "radio", "wifi", root.wifiActive ? "on" : "off"];
                            wifiToggleProcess.running = true;
                        }
                    }
                }
            }

            // Bluetooth
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.btActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.btActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰂯"; font.pixelSize: 15; color: root.btActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Bluetooth"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                    Text { text: "󰅂"; font.pixelSize: 11; color: Tokens.text_secondary }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (eventPoint) => {
                        if (eventPoint.event.button === Qt.RightButton) {
                            root.btDrawerOpen = true;
                        } else {
                            root.btActive = !root.btActive;
                            btToggleProcess.command = ["bluetoothctl", "power", root.btActive ? "on" : "off"];
                            btToggleProcess.running = true;
                        }
                    }
                }
            }

            // Mute Toggle Tile
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: Audio.muted ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.18) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Audio.muted ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: Audio.muted ? "󰝟" : "󰕾"; font.pixelSize: 15; color: Audio.muted ? Tokens.danger : Tokens.accent }
                    Text { text: Audio.muted ? "Muted" : "Mute"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: Audio.toggleMute()
                }
            }

            // Do Not Disturb
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.dndActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.dndActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰂛"; font.pixelSize: 15; color: root.dndActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "DND"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.dndActive = !root.dndActive
                }
            }

            // Night Light
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.nightLightActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.nightLightActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰖔"; font.pixelSize: 15; color: root.nightLightActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Night"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.nightLightActive = !root.nightLightActive
                }
            }

            // Caffeine / Awake
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.caffeineActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.caffeineActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.45) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰅶"; font.pixelSize: 15; color: root.caffeineActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Awake"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.caffeineActive = !root.caffeineActive
                }
            }
        }
    }

    // Interactive Wi-Fi Selection Drawer Overlay
    WifiDrawer {
        visible: root.wifiDrawerOpen
        opacity: root.wifiDrawerOpen ? 1.0 : 0.0
        onCloseRequested: root.wifiDrawerOpen = false

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    // Interactive Bluetooth Device Drawer Overlay
    BluetoothDrawer {
        visible: root.btDrawerOpen
        opacity: root.btDrawerOpen ? 1.0 : 0.0
        onCloseRequested: root.btDrawerOpen = false

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }
}
