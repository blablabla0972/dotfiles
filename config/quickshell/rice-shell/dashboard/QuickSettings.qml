pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Rectangle {
    id: root

    implicitWidth: 230
    implicitHeight: 300
    radius: 14
    color: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
    border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
    border.width: 1

    property bool dndActive: false
    property bool nightLightActive: false
    property bool caffeineActive: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Section Title
        Text {
            text: "Quick Controls"
            font.pixelSize: 12
            font.bold: true
            color: Tokens.text_secondary
        }

        // Volume Slider Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: Audio.muted ? "󰝟" : "󰕾"
                font.pixelSize: 14
                color: Tokens.accent
            }

            Rectangle {
                id: volTrack
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.9)

                Rectangle {
                    height: parent.height
                    width: Math.min(parent.width, parent.width * Audio.volume)
                    radius: 4
                    color: Audio.muted ? Tokens.outline : Tokens.accent
                }

                TapHandler {
                    onTapped: (point) => {
                        var ratio = Math.max(0.0, Math.min(1.0, point.position.x / volTrack.width));
                        Audio.setVolume(ratio);
                    }
                }
            }
        }

        // 2-Column Quick Toggle Tiles
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            // 1. Wi-Fi
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰤨"; font.pixelSize: 16; color: Tokens.accent }
                    Text { text: "Wi-Fi"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }
            }

            // 2. Bluetooth
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2)
                border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰂯"; font.pixelSize: 16; color: Tokens.accent }
                    Text { text: "Bluetooth"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }
            }

            // 3. Do Not Disturb
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: root.dndActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰂛"; font.pixelSize: 16; color: root.dndActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "DND"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.dndActive = !root.dndActive
                }
            }

            // 4. Night Light
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: root.nightLightActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰖔"; font.pixelSize: 16; color: root.nightLightActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Night"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.nightLightActive = !root.nightLightActive
                }
            }

            // 5. Theme Mode
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰔎"; font.pixelSize: 16; color: Tokens.accent }
                    Text { text: Tokens.mode === "dark" ? "Dark" : "Light"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }
            }

            // 6. Caffeine
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: root.caffeineActive ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.2) : Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.7)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "󰅶"; font.pixelSize: 16; color: root.caffeineActive ? Tokens.accent : Tokens.text_secondary }
                    Text { text: "Awake"; font.pixelSize: 11; font.bold: true; color: Tokens.text_primary }
                }

                TapHandler {
                    onTapped: root.caffeineActive = !root.caffeineActive
                }
            }
        }
    }
}
