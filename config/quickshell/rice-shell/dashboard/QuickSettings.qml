pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

    property string sharedError: ""

    signal requestSideDrawer(string type)

    function setBrightness(value: real): void {
        DesktopControls.setBrightness(value);
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

    Connections {
        target: DesktopControls
        function onErrorOccurred(message) {
            root.sharedError = message;
            sharedErrorTimeout.restart();
        }
    }

    Connections {
        target: Audio
        function onErrorChanged() {
            if (!Audio.error) return;
            root.sharedError = Audio.error;
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
                available: Audio.available && !Audio.changeBusy
                commitOnRelease: true
                valueText: !Audio.available ? qsTr("Unavailable")
                    : (Audio.muted ? qsTr("Muted") : Math.round(Audio.volume * 100) + "%")
                        + (Audio.available && !Audio.muted && Audio.volume > 1 ? qsTr(" · Boost") : "")
                onValueRequested: (value) => Audio.requestOutputVolume(value)
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
                        pending: Audio.changeBusy
                        hasDetails: true
                        onActivated: Audio.requestOutputMute()
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
