pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"
import "../theme"

Item {
    id: root
    property bool settingsPage: false

    anchors.fill: settingsPage ? undefined : parent
    implicitWidth: 360
    implicitHeight: settingsPage ? hotspotContent.implicitHeight : 500
    focus: visible && !settingsPage
    activeFocusOnTab: settingsPage

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Hotspot settings")

    property string networkName: Hotspot.ssid || "Rice-Hotspot"
    property string passwordText: ""
    property bool revealPassword: false
    property string formMessage: ""
    property string _loadedSsid: Hotspot.ssid

    onVisibleChanged: {
        if (!visible) {
            root.passwordText = "";
            root.revealPassword = false;
            if (conflictDialog.visible) conflictDialog.reject();
        }
    }

    function handleEscape(): bool {
        if (conflictDialog.visible) {
            conflictDialog.reject();
            return true;
        }
        return false;
    }

    function saveProfile(): void {
        if (!Hotspot.saveConfiguration(networkName, passwordText)) {
            formMessage = qsTr("NetworkManager is busy or unavailable.");
            return;
        }
        formMessage = qsTr("Saving profile in NetworkManager…");
    }

    Component.onCompleted: {
        Hotspot.refresh();
        if (Hotspot.confirmationRequired) conflictDialog.open();
    }

    Connections {
        target: Hotspot
        function onSnapshotChanged() {
            if (Hotspot.ssid && (root.networkName === root._loadedSsid || root.networkName.length === 0 || root.networkName === "Rice-Hotspot"))
                root.networkName = Hotspot.ssid;
            root._loadedSsid = Hotspot.ssid;
        }
        function onOperationFinished(operation, ok, message) {
            if (operation !== "configure") return;
            root.formMessage = ok
                ? qsTr("Profile saved in NetworkManager.")
                : String(message || qsTr("The profile could not be saved."));
            if (ok) root.passwordText = "";
        }
        function onConfirmationRequiredChanged() {
            if (Hotspot.confirmationRequired) conflictDialog.open();
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: root.settingsPage ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded

        ColumnLayout {
            id: hotspotContent
            width: scroll.availableWidth
            spacing: 14

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.settingsPage ? Math.max(68, stateContent.implicitHeight + 24)
                    : stateContent.implicitHeight + 24
                radius: root.settingsPage ? 9 : 12
                color: root.settingsPage ? Tokens.surface_low : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                               Tokens.surface_high.b, 0.78)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                      Tokens.outline.b, 0.22)
                border.width: 1

                ColumnLayout {
                    id: stateContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            visible: !root.settingsPage
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: Hotspot.active ? Tokens.accent : Tokens.text_secondary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 3

                            Text {
                                visible: root.settingsPage
                                text: qsTr("Share connection")
                                color: Tokens.text_primary
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.settingsPage && Hotspot.tileStatus === "Turn Wi-Fi on"
                                    ? qsTr("Turn on Wi-Fi before starting a hotspot.") : Hotspot.tileStatus
                                color: root.settingsPage ? Tokens.text_secondary : Tokens.text_primary
                                font.pixelSize: root.settingsPage ? 13 : 14
                                font.weight: root.settingsPage ? Font.Normal : Font.DemiBold
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }

                        BusyIndicator {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            running: Hotspot.busy
                            visible: running
                        }

                        Switch {
                            id: activeSwitch
                            width: 44
                            height: 24
                            implicitWidth: 44
                            implicitHeight: 24
                            checked: Hotspot.active
                            enabled: !Hotspot.busy && (Hotspot.active || Hotspot.canStart)
                            Accessible.name: Hotspot.active
                                ? qsTr("Stop hotspot") : qsTr("Start hotspot")
                            onToggled: {
                                const target = !Hotspot.active;
                                checked = Qt.binding(() => Hotspot.active);
                                if (target !== Hotspot.active) {
                                    Hotspot.toggle();
                                }
                            }

                            indicator: Rectangle {
                                implicitWidth: 44
                                implicitHeight: 24
                                width: 44
                                height: 24
                                radius: height / 2
                                color: activeSwitch.checked
                                    ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.85)
                                    : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
                                border.color: activeSwitch.activeFocus ? Tokens.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 160 } }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    y: 3
                                    x: activeSwitch.checked ? parent.width - width - 3 : 3
                                    color: activeSwitch.checked ? Tokens.on_accent : Tokens.text_secondary
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            contentItem: Item {}
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Hotspot.errorMessage.length > 0
                        text: Hotspot.errorMessage
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 13 : 11
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !Hotspot.profileConfigured && !Hotspot.active
                        text: qsTr("Save a network name and WPA2 password before starting.")
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 13 : 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: configurationContent.implicitHeight + 24
                radius: root.settingsPage ? 9 : 12
                color: root.settingsPage ? Tokens.surface_low : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                               Tokens.surface_high.b, 0.62)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                      Tokens.outline.b, 0.18)
                border.width: 1

                ColumnLayout {
                    id: configurationContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 9

                    Text {
                        text: root.settingsPage ? qsTr("Hotspot profile") : qsTr("Network settings")
                        color: Tokens.text_primary
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: qsTr("Network name")
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 13 : 11
                        font.weight: Font.Medium
                    }

                    TextField {
                        id: ssidField
                        Layout.fillWidth: true
                        implicitHeight: 38
                        text: root.networkName
                        placeholderText: qsTr("Network name")
                        enabled: !Hotspot.active && !Hotspot.busy
                        Accessible.name: qsTr("Hotspot network name")
                        color: Tokens.text_primary
                        selectionColor: Tokens.accent
                        font.pixelSize: 12
                        onTextEdited: root.networkName = text
                        background: Rectangle {
                            radius: root.settingsPage ? 8 : 14
                            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.75)
                            border.color: ssidField.activeFocus ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                            border.width: ssidField.activeFocus ? 2 : 1
                        }
                    }

                    Text {
                        text: qsTr("Password")
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 13 : 11
                        font.weight: Font.Medium
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: passwordField
                            Layout.fillWidth: true
                            implicitHeight: 38
                            text: root.passwordText
                            placeholderText: Hotspot.profileConfigured
                                ? qsTr("Leave blank to keep current")
                                : qsTr("WPA2 password (8–63 chars)")
                            echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
                            passwordMaskDelay: 0
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            enabled: !Hotspot.active && !Hotspot.busy
                            Accessible.name: qsTr("Hotspot password")
                            color: Tokens.text_primary
                            selectionColor: Tokens.accent
                            font.pixelSize: 12
                            onTextEdited: root.passwordText = text
                            background: Rectangle {
                                radius: root.settingsPage ? 8 : 14
                                color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.75)
                                border.color: passwordField.activeFocus ? Tokens.accent : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.3)
                                border.width: passwordField.activeFocus ? 2 : 1
                            }
                        }

                        RoundedButton {
                            id: showPassBtn
                            implicitHeight: 38
                            implicitWidth: 58
                            text: root.revealPassword ? qsTr("Hide") : qsTr("Show")
                            enabled: !Hotspot.active
                            Accessible.name: root.revealPassword
                                ? qsTr("Hide hotspot password")
                                : qsTr("Show hotspot password")
                            onClicked: root.revealPassword = !root.revealPassword
                            contentItem: Text {
                                text: showPassBtn.text
                                font.pixelSize: root.settingsPage ? 13 : 11
                                font.weight: Font.Medium
                                color: showPassBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: root.settingsPage ? 8 : 14
                                color: showPassBtn.hovered ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75) : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.45)
                                border.color: showPassBtn.hovered ? Tokens.outline : Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                                border.width: 1
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Your saved password stays private and cannot be displayed here.")
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 12 : 10
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.formMessage
                            color: Tokens.text_secondary
                            font.pixelSize: root.settingsPage ? 12 : 10
                            wrapMode: Text.Wrap
                        }

                        RoundedButton {
                            id: saveProfileBtn
                            implicitHeight: 32
                            implicitWidth: 110
                            text: qsTr("Save settings")
                            enabled: !Hotspot.active && !Hotspot.busy && Hotspot.canConfigure
                            Accessible.name: qsTr("Save hotspot profile")
                            onClicked: root.saveProfile()
                            contentItem: Text {
                                text: saveProfileBtn.text
                                font.pixelSize: root.settingsPage ? 13 : 11
                                font.weight: Font.DemiBold
                                color: saveProfileBtn.enabled ? Tokens.on_accent : Tokens.text_secondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: root.settingsPage ? 8 : 14
                                color: saveProfileBtn.enabled
                                    ? (saveProfileBtn.hovered ? Qt.darker(Tokens.accent, 1.1) : Tokens.accent)
                                    : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.2)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: Hotspot.active
                implicitHeight: activeContent.implicitHeight + 24
                radius: root.settingsPage ? 9 : 12
                color: root.settingsPage ? Tokens.surface_low : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g,
                               Tokens.surface_high.b, 0.62)
                border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g,
                                      Tokens.outline.b, 0.18)
                border.width: 1

                ColumnLayout {
                    id: activeContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    Text {
                        text: root.settingsPage ? qsTr("Active connection") : qsTr("ACTIVE DETAILS")
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 12 : 10
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Network: %1").arg(Hotspot.ssid || qsTr("Unavailable"))
                        color: Tokens.text_primary
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Adapter: %1").arg(Hotspot.deviceName || qsTr("Unknown"))
                        color: Tokens.text_primary
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Security: %1").arg(Hotspot.security || qsTr("Unverified"))
                        color: Tokens.text_primary
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Hotspot.upstreamStatus
                        color: Tokens.text_secondary
                        font.pixelSize: root.settingsPage ? 13 : 11
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }

    Dialog {
        id: conflictDialog
        parent: root
        anchors.centerIn: parent
        width: Math.min(312, parent.width - 16)
        modal: true
        title: qsTr("Wi-Fi connection may be interrupted")
        standardButtons: Dialog.NoButton
        padding: 16

        background: Rectangle {
            radius: 14
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.96)
            border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.35)
            border.width: 1
        }

        header: Item {
            implicitHeight: 40
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: conflictDialog.title
                color: Tokens.text_primary
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        contentItem: Text {
            width: conflictDialog.availableWidth
            text: qsTr("Starting the hotspot on %1 may disconnect its active Wi-Fi client. If that client is the upstream, shared internet will be unavailable until another IPv4 default route is active. The saved client profile remains in NetworkManager.")
                .arg(Hotspot.deviceName || qsTr("this adapter"))
            color: Tokens.text_secondary
            font.pixelSize: 11
            lineHeight: 1.25
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        footer: Item {
            implicitHeight: 46
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                RoundedButton {
                    id: cancelConflictBtn
                    implicitHeight: 30
                    implicitWidth: 68
                    text: qsTr("Cancel")
                    Accessible.name: qsTr("Cancel starting hotspot")
                    onClicked: conflictDialog.reject()
                    contentItem: Text {
                        text: cancelConflictBtn.text
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: cancelConflictBtn.hovered ? Tokens.text_primary : Tokens.text_secondary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 14
                        color: cancelConflictBtn.hovered
                            ? Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.75)
                            : Qt.rgba(Tokens.surface_high.r, Tokens.surface_high.g, Tokens.surface_high.b, 0.40)
                        border.color: Qt.rgba(Tokens.outline.r, Tokens.outline.g, Tokens.outline.b, 0.25)
                        border.width: 1
                    }
                }

                RoundedButton {
                    id: confirmConflictBtn
                    implicitHeight: 30
                    implicitWidth: 96
                    text: qsTr("Start Hotspot")
                    Accessible.name: qsTr("Confirm and start hotspot")
                    onClicked: conflictDialog.accept()
                    contentItem: Text {
                        text: confirmConflictBtn.text
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Tokens.on_accent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 14
                        color: confirmConflictBtn.hovered
                            ? Qt.darker(Tokens.accent, 1.1)
                            : Tokens.accent
                    }
                }
            }
        }

        onAccepted: Hotspot.confirmStart()
        onRejected: Hotspot.cancelConfirmation()
    }
}
