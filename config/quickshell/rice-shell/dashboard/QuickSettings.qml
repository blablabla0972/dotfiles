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
        anchors.margins: 12
        spacing: 10

        // Section Title
        Text {
            text: "Quick Controls"
            font.pixelSize: 12
            font.bold: true
            color: Tokens.text_secondary
        }

        // 1. Volume Slider Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: Audio.muted ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.2) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: Audio.muted ? "󰝟" : (Audio.volume > 0.5 ? "󰕾" : (Audio.volume > 0.05 ? "󰖀" : "󰕿"))
                    font.pixelSize: 14
                    color: Audio.muted ? Tokens.danger : Tokens.accent
                }

                TapHandler {
                    onTapped: Audio.toggleMute()
                }
            }

            Rectangle {
                id: volTrack
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                Rectangle {
                    height: parent.height
                    width: Math.min(parent.width, Math.max(0, parent.width * Audio.volume))
                    radius: 4
                    color: Audio.muted ? Tokens.outline : Tokens.accent

                    Behavior on width {
                        NumberAnimation { duration: 80 }
                    }
                }

                TapHandler {
                    onTapped: (point) => {
                        var ratio = Math.max(0.0, Math.min(1.0, point.position.x / volTrack.width));
                        Audio.setVolume(ratio);
                    }
                }
            }

            Text {
                text: Audio.muted ? "0%" : Math.round(Audio.volume * 100) + "%"
                font.pixelSize: 10
                font.bold: true
                color: Tokens.text_secondary
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignRight
            }
        }

        // 2. Brightness Slider Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰃠"
                    font.pixelSize: 14
                    color: Tokens.accent
                }
            }

            Rectangle {
                id: brightTrack
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                Rectangle {
                    height: parent.height
                    width: Math.min(parent.width, Math.max(0, parent.width * root.brightness))
                    radius: 4
                    color: Tokens.accent

                    Behavior on width {
                        NumberAnimation { duration: 80 }
                    }
                }

                TapHandler {
                    onTapped: (point) => {
                        var ratio = Math.max(0.05, Math.min(1.0, point.position.x / brightTrack.width));
                        root.setBrightness(ratio);
                    }
                }
            }

            Text {
                text: Math.round(root.brightness * 100) + "%"
                font.pixelSize: 10
                font.bold: true
                color: Tokens.text_secondary
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignRight
            }
        }

        Item { Layout.fillHeight: true }

        // 3. Quick Toggle Tiles (2 columns)
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            // Wi-Fi
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: root.wifiActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.wifiActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰤨"; font.pixelSize: 14; color: root.wifiActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Wi-Fi"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.wifiActive = !root.wifiActive
                }
            }

            // Bluetooth
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: root.btActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.btActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰂯"; font.pixelSize: 14; color: root.btActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Bluetooth"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.btActive = !root.btActive
                }
            }

            // Mute Toggle Tile
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: Audio.muted ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Audio.muted ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: Audio.muted ? "󰝟" : "󰕾"; font.pixelSize: 14; color: Audio.muted ? Tokens.danger : Tokens.accent }
                    Text { text: Audio.muted ? "Muted" : "Mute"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: Audio.toggleMute()
                }
            }

            // Do Not Disturb
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: root.dndActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.dndActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰂛"; font.pixelSize: 14; color: root.dndActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "DND"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.dndActive = !root.dndActive
                }
            }

            // Night Light
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: root.nightLightActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.nightLightActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰖔"; font.pixelSize: 14; color: root.nightLightActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Night"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.nightLightActive = !root.nightLightActive
                }
            }

            // Caffeine / Awake
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: root.caffeineActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: root.caffeineActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4) : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "󰅶"; font.pixelSize: 14; color: root.caffeineActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Awake"; font.pixelSize: 10; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.caffeineActive = !root.caffeineActive
                }
            }
        }
    }
}
