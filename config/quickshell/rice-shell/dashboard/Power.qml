pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../theme"

Item {
    id: root
    implicitWidth: 860
    implicitHeight: width < 620 ? 750 : 390
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery.ready && battery.isLaptopBattery && battery.isPresent
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property int charge: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property color cardColor: Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.8)
    readonly property string batteryStatus: !hasBattery ? qsTr("No battery detected")
        : charging ? qsTr("Charging")
        : battery.state === UPowerDeviceState.FullyCharged ? qsTr("Fully charged")
        : battery.state === UPowerDeviceState.PendingCharge ? qsTr("Plugged in · Not charging")
        : UPower.onBattery ? qsTr("On battery") : qsTr("Plugged in")
    readonly property string estimate: {
        if (!hasBattery) return qsTr("Power modes are still available on AC power.");
        const seconds = charging ? battery.timeToFull : battery.timeToEmpty;
        if (seconds <= 0) return qsTr("Estimating battery time…");
        const minutes = Math.max(1, Math.round(seconds / 60));
        const time = minutes >= 60
            ? qsTr("%1h %2m").arg(Math.floor(minutes / 60)).arg(minutes % 60)
            : qsTr("%1 min").arg(minutes);
        return charging ? qsTr("About %1 until full").arg(time) : qsTr("About %1 remaining").arg(time);
    }
    property int pendingProfile: -1
    property string profileError: ""

    function selectProfile(profile: int): void {
        if (pendingProfile !== -1 || profile === PowerProfiles.profile) return;
        if (profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return;
        profileError = "";
        pendingProfile = profile;
        profileTimeout.restart();
        PowerProfiles.profile = profile;
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged(): void {
            if (root.pendingProfile === PowerProfiles.profile) {
                root.pendingProfile = -1;
                profileTimeout.stop();
            }
        }
    }
    Timer {
        id: profileTimeout
        interval: 5000
        onTriggered: {
            if (root.pendingProfile !== PowerProfiles.profile)
                root.profileError = qsTr("Could not change power mode. Please try again.");
            root.pendingProfile = -1;
        }
    }

    GridLayout {
        anchors.fill: parent
        columns: root.width < 620 ? 1 : 2
        columnSpacing: 14
        rowSpacing: 14

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 320
            Layout.preferredHeight: 350
            radius: 24
            color: root.cardColor
            border.width: 1
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.24)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Battery")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Tokens.text_primary
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.charging ? "󰂄" : "󰁹"
                    font.pixelSize: 48
                    color: root.hasBattery && root.charge <= 20 ? Tokens.danger : Tokens.accent
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hasBattery ? root.charge + "%" : "—"
                    font.pixelSize: 52
                    font.weight: Font.DemiBold
                    color: Tokens.text_primary
                    Accessible.name: qsTr("Battery charge: %1 percent").arg(root.charge)
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Tokens.surface
                    Rectangle {
                        width: parent.width * (root.hasBattery ? root.charge / 100 : 0)
                        height: parent.height
                        radius: 4
                        color: root.charge <= 20 ? Tokens.danger : Tokens.accent
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.batteryStatus
                    font.pixelSize: 13
                    color: Tokens.text_primary
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.battery.state === UPowerDeviceState.FullyCharged
                        ? qsTr("Ready to go") : root.estimate
                    font.pixelSize: 11
                    color: Tokens.text_secondary
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 480
            Layout.preferredHeight: 370
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: qsTr("Power mode")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Tokens.text_primary
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("Choose how your laptop uses energy.")
                font.pixelSize: 11
                color: Tokens.text_secondary
                wrapMode: Text.Wrap
            }
            Repeater {
                model: [
                    { profile: PowerProfile.PowerSaver, title: qsTr("Power Saver"), icon: "󰌪",
                        detail: qsTr("Lower power use for longer battery life.") },
                    { profile: PowerProfile.Balanced, title: qsTr("Balanced"), icon: "󰾅",
                        detail: qsTr("A balance of everyday speed and battery life.") },
                    { profile: PowerProfile.Performance, title: qsTr("Performance"), icon: "󱐋",
                        detail: qsTr("More speed for demanding tasks. Uses more energy.") }
                ]
                delegate: Rectangle {
                    id: mode
                    required property var modelData
                    readonly property bool selected: PowerProfiles.profile === modelData.profile
                    readonly property bool supported: modelData.profile !== PowerProfile.Performance
                        || PowerProfiles.hasPerformanceProfile
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 84
                    radius: 20
                    color: selected ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.17)
                        : hover.hovered ? Tokens.surface_high : root.cardColor
                    border.width: activeFocus || selected ? 2 : 1
                    border.color: selected || activeFocus ? Tokens.accent
                        : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.24)
                    opacity: supported ? 1 : 0.5
                    activeFocusOnTab: supported
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.title
                    Accessible.description: modelData.detail
                    Accessible.checked: selected
                    Accessible.checkable: true
                    Accessible.onPressAction: if (mode.supported) root.selectProfile(mode.modelData.profile)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14
                        Text {
                            text: mode.modelData.icon
                            font.pixelSize: 26
                            color: mode.selected ? Tokens.accent : Tokens.text_secondary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Text {
                                Layout.fillWidth: true
                                text: mode.modelData.title
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Tokens.text_primary
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: !mode.supported ? qsTr("Unavailable on this device")
                                    : root.pendingProfile === mode.modelData.profile ? qsTr("Applying…") : mode.modelData.detail
                                font.pixelSize: 11
                                color: Tokens.text_secondary
                                wrapMode: Text.Wrap
                            }
                        }
                        Text {
                            text: mode.selected ? "󰄬" : ""
                            font.pixelSize: 20
                            color: Tokens.accent
                        }
                    }
                    HoverHandler { id: hover; cursorShape: mode.supported ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        enabled: mode.supported && root.pendingProfile === -1
                        onTapped: root.selectProfile(mode.modelData.profile)
                    }
                    Keys.onReturnPressed: root.selectProfile(modelData.profile)
                    Keys.onSpacePressed: root.selectProfile(modelData.profile)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.profileError
                font.pixelSize: 11
                color: Tokens.danger
                wrapMode: Text.Wrap
            }
        }
    }
}
