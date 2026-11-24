pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"
import "Registry.js" as Registry

ColumnLayout {
    id: root
    property var output
    property bool available: false
    property string token: ""
    property string previewName: ""
    property int remaining: 0
    property string operation: ""
    property string feedback: ""
    property var payload
    property var supportedScales: []
    readonly property string helper: Quickshell.shellDir + "/settings/displays.py"
    readonly property bool busy: operation.length > 0 || runner.running
    readonly property bool editable: available && !!output && !output.disabled && output.dpmsStatus === true
        && output.mirrorOf === "none" && !output.vrr && output.currentFormat === "XRGB8888"
        && output.colorManagementPreset === "srgb" && output.sdrBrightness === 1 && output.sdrSaturation === 1
    readonly property var modes: output ? Array.from(output.availableModes || []) : []
    readonly property var scales: {
        const match = /^(\d+)x(\d+)@/.exec(mode.displayText);
        return !match ? [] : supportedScales.filter(amount =>
            [Number(match[1]), Number(match[2])].every(axis =>
                Math.abs(axis / amount - Math.round(axis / amount)) < 0.001));
    }
    readonly property color ink: Registry.readable(Tokens.text_primary, Tokens.surface_low, 4.5)
    signal changed()

    visible: available
    spacing: 9
    Component.onCompleted: request("available", {})
    Component.onDestruction: {
        if (token) Quickshell.execDetached(["python3", helper, "cancel", token]);
    }
    onOutputChanged: if (!token) Qt.callLater(root.resetSelection)

    function resetSelection(): void {
        mode.currentIndex = Math.max(0, modes.findIndex(item => Registry.activeDisplayMode(output, item)));
        resetScale();
    }

    function resetScale(): void {
        if (output) scalePicker.currentIndex = Math.max(0, scales.findIndex(item => Math.abs(item - output.scale) < 0.006));
    }

    function request(action: string, data): void {
        if (busy) return;
        operation = action;
        payload = data;
        watchdog.restart();
        runner.exec(["python3", helper, action]);
    }

    function receive(reply): void {
        if (!operation) return;
        const last = operation;
        operation = "";
        watchdog.stop();
        if (last === "available") {
            available = reply?.status === "available";
            supportedScales = Array.isArray(reply?.scales) ? reply.scales : [];
            if (available) {
                Qt.callLater(root.resetSelection);
                statusTimer.start();
            }
            return;
        }
        if (reply?.status === "preview") {
            token = reply.token;
            previewName = reply.name;
            remaining = reply.seconds;
            if (!decision.visible) decision.open();
            if (last === "preview") changed();
        } else if (["idle", "kept", "reverted"].includes(reply?.status)) {
            const wasPreview = token.length > 0;
            token = "";
            decision.close();
            if (wasPreview || reply.status !== "idle") changed();
            if (reply.status === "kept") feedback = qsTr("Display mode saved.");
            else if (reply.status === "reverted") feedback = qsTr("Previous display mode restored.");
        } else {
            const reason = reply?.reason;
            if (last === "status" && reason === "busy") {
                statusTimer.restart();
                return;
            }
            feedback = reason === "guard_unavailable" ? qsTr("The rollback timer could not start.")
                : reason === "overrides_changed" ? qsTr("Display overrides changed outside Settings. The preview was cancelled.")
                : reason === "recovery_unconfirmed" || reason === "external_display_change"
                    ? qsTr("The previous display mode could not be confirmed. Use the recovery command.")
                : qsTr("The display request could not be confirmed.");
        }
        if (last !== "status" || token) statusTimer.restart();
    }

    Timer {
        id: statusTimer
        interval: 400
        onTriggered: root.request("status", root.token ? { token: root.token } : {})
    }

    Timer {
        id: watchdog
        interval: 9000
        onTriggered: {
            runner.running = false;
            root.receive(null);
        }
    }

    Process {
        id: runner
        stdinEnabled: true
        onStarted: if (root.operation !== "available") write(JSON.stringify(root.payload) + "\n")
        stdout: StdioCollector { id: result }
        onExited: code => {
            let parsed = null;
            try { if (code === 0) parsed = JSON.parse(result.text); } catch (error) {}
            root.receive(parsed);
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !root.editable
        wrapMode: Text.Wrap
        text: qsTr("This output's current configuration cannot be safely previewed.")
        color: root.ink
    }

    Label {
        visible: root.editable
        text: qsTr("Change mode and scale")
        font.weight: Font.DemiBold
        color: root.ink
    }

    RowLayout {
        visible: root.editable
        Layout.fillWidth: true
        SettingsComboBox {
            id: mode
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            model: root.modes
            enabled: !root.busy && !root.token
            Accessible.name: qsTr("Display mode")
            onActivated: Qt.callLater(root.resetScale)
        }
        SettingsComboBox {
            id: scalePicker
            model: root.scales.map(amount => qsTr("%1%").arg(amount * 100))
            enabled: !root.busy && !root.token
            Accessible.name: qsTr("Display scale")
        }
        SettingsActionButton {
            text: qsTr("Preview")
            primary: true
            enabled: root.editable && !root.busy && !root.token && mode.currentIndex >= 0 && scalePicker.currentIndex >= 0
                && (!Registry.activeDisplayMode(root.output, mode.displayText)
                    || Math.abs(root.scales[scalePicker.currentIndex] - root.output.scale) >= 0.006)
            onClicked: {
                root.feedback = "";
                root.request("preview", { name: root.output.name, mode: mode.displayText,
                    scale: root.scales[scalePicker.currentIndex] });
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.feedback.length > 0
        text: root.feedback
        wrapMode: Text.Wrap
        color: root.ink
    }

    property SettingsDialog confirmation: SettingsDialog {
        id: decision
        title: qsTr("Keep this display mode?")
        closePolicy: Popup.NoAutoClose
        bodyHeight: 92
        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                text: qsTr("%1 reverts in %2 seconds unless you keep this mode.")
                    .arg(root.previewName).arg(root.remaining)
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                visible: root.feedback.length > 0
                text: root.feedback
                wrapMode: Text.Wrap
            }
        }
        footer: RowLayout {
            spacing: 9
            Item { Layout.fillWidth: true }
            SettingsActionButton {
                text: qsTr("Revert")
                enabled: !root.busy
                onClicked: root.request("revert", { token: root.token })
            }
            SettingsActionButton {
                text: qsTr("Keep")
                primary: true
                enabled: !root.busy && root.remaining > 0
                onClicked: root.request("keep", { token: root.token })
            }
        }
    }
}
