pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"
import "../theme"
import "Registry.js" as Registry

Rectangle {
    id: root
    required property string section
    required property ShellPresentation presentation
    readonly property var options: ({
        "top-bar": [
            ["showTray", qsTr("System tray"), qsTr("Show background app icons in the bar.")],
            ["showConnectivity", qsTr("Connection status"), qsTr("Show online or offline status and quick access to Wi-Fi.")],
            ["showBattery", qsTr("Battery indicator"), qsTr("Show battery charge on outputs with a system battery.")],
            ["showClockSeconds", qsTr("Clock seconds"), qsTr("Show seconds beside hours and minutes.")]
        ],
        "dynamic-island": [
            ["showMediaPreview", qsTr("Media preview"), qsTr("Show the current track and artwork when media is available.")]
        ],
        "osd": [
            ["volumeOsd", qsTr("Volume"), qsTr("Show feedback when output volume or mute changes.")],
            ["brightnessOsd", qsTr("Brightness"), qsTr("Show feedback when a brightness shortcut changes the backlight.")],
            ["microphoneOsd", qsTr("Microphone"), qsTr("Show feedback when the microphone is muted or unmuted.")]
        ]
    })[section] || []
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    readonly property color muted: Registry.readable(Tokens.text_secondary, Tokens.surface_low, 4.5)
    implicitHeight: content.implicitHeight + 28
    radius: 10
    color: Tokens.surface_low
    border.color: Qt.tint(color, Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.55))

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Repeater {
            model: root.options
            delegate: RowLayout {
                id: option
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumHeight: 45
                spacing: 14
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Label {
                        Layout.fillWidth: true
                        text: option.modelData[1]
                        color: root.ink
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: option.modelData[2]
                        color: root.muted
                        wrapMode: Text.Wrap
                    }
                }
                SettingsToggle {
                    objectName: "shell-" + option.modelData[0]
                    Accessible.name: option.modelData[1]
                    enabled: !!root.presentation
                    checked: root.presentation?.[option.modelData[0]] === true
                    onToggled: root.presentation[option.modelData[0]] = checked
                }
            }
        }
    }
}
