pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var snapshot: null
    property string action: ""
    property string message: ""
    property var payload: null
    readonly property bool busy: action.length > 0
    readonly property bool writable: !busy && snapshot?.writable === true
    signal reconciled()

    function refresh(): void { run("read", null); }
    function save(layout): void {
        if (writable) run("save", { layout: layout, active: snapshot.active, revision: snapshot.revision });
    }
    function reset(): void {
        if (writable && snapshot.saved) run("reset", { active: snapshot.active, revision: snapshot.revision });
    }

    function run(next: string, data): void {
        if (busy) return;
        action = next;
        payload = data;
        message = "";
        process.exec(["python3", Quickshell.shellDir + "/settings/window_layout.py", next]);
    }

    function receive(result): void {
        if (!busy) return;
        const ended = action;
        action = "";
        payload = null;
        if (result?.status === "ok" || result?.status === "applied" || result?.status === "reset") {
            snapshot = result;
            message = ended === "save" ? qsTr("Window spacing applied and verified.")
                : ended === "reset" ? qsTr("Hyprland defaults restored.") : "";
            reconciled();
            return;
        }
        const reason = result?.reason;
        if (reason === "conflict") {
            message = qsTr("Window spacing changed elsewhere. Refresh before editing.");
        } else if (reason === "display_preview") {
            message = qsTr("Finish the display preview first.");
        } else if (reason === "layout_reverted") {
            message = qsTr("Hyprland did not confirm the changes. The previous layout was restored.");
        } else if (reason === "recovery_unconfirmed") {
            message = qsTr("Could not confirm recovery. Check the Hyprland configuration.");
        } else {
            message = qsTr("Could not read or apply the window layout.");
        }
        if (reason === "conflict" || reason === "recovery_unconfirmed" || ended === "read")
            snapshot = null;
    }

    property Process process: Process {
        id: runner
        stdinEnabled: true
        onStarted: if (root.payload) write(JSON.stringify(root.payload) + "\n")
        stdout: StdioCollector { id: response }
        onExited: code => {
            let decoded = null;
            try { if (code === 0) decoded = JSON.parse(response.text); } catch (error) {}
            root.receive(decoded);
        }
    }
}
