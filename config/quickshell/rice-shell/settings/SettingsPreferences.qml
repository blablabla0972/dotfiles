pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool watching: false
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string path: configHome + "/rice-settings/preferences.json"
    property var values: ({ reduceMotion: false, compactRows: false })
    property var draft: null
    property var importPreview: null
    property string revision: ""
    property string issue: ""
    property string status: "loading"
    property bool recoverable: false
    property bool refreshQueued: false
    property string action: ""
    property var request: null
    readonly property bool busy: action.length > 0 || runner.running
    readonly property bool writable: status === "ok" && !busy
    readonly property bool reduceMotion: values.reduceMotion
    readonly property bool compactRows: values.compactRows

    onWatchingChanged: if (watching) refresh()

    function refresh(): void {
        if (busy) refreshQueued = true;
        else start("read", null);
    }

    function propose(key: string, value: bool): void {
        if (!writable || !["reduceMotion", "compactRows"].includes(key)) return;
        draft = { [key]: value };
        retry();
    }

    function retry(): void {
        if (writable && draft) start("update", { revision: revision, patch: draft });
    }

    function discard(): void {
        draft = null;
        issue = "";
    }

    function restore(): void {
        if (!busy && recoverable && revision) start("restore", { revision: revision });
    }

    function inspect(url: string): void {
        if (writable) start("inspect", { revision: revision, url: url });
    }

    function exportCopy(url: string): void {
        if (writable) start("export", { revision: revision, url: url });
    }

    function confirmImport(): void {
        if (!writable || !importPreview) return;
        const approved = importPreview;
        importPreview = null;
        draft = approved.values;
        start("update", { revision: approved.revision, patch: draft });
    }

    function start(operation: string, payload): void {
        issue = "";
        action = operation;
        request = payload;
        failTimer.restart();
        runner.exec(["python3", Quickshell.shellDir + "/settings/preferences.py", operation]);
    }

    function complete(result): void {
        if (!action) return;
        const operation = action;
        action = "";
        request = null;
        failTimer.stop();
        if (result?.status === "exported") {
            issue = qsTr("Preferences copy saved.");
        } else if (result?.status === "preview") {
            importPreview = result;
        } else if (result?.status !== "conflict" && (operation === "inspect" || operation === "export")) {
            issue = result?.reason === "destination_exists" ? qsTr("A file already exists at that location. Choose a new name.")
                : operation === "inspect" ? qsTr("Could not open a valid Rice Settings preferences file.")
                : qsTr("Could not save the preferences copy.");
        } else if (result && ["ok", "applied"].includes(result.status)
                && typeof result.values?.reduceMotion === "boolean"
                && typeof result.values?.compactRows === "boolean") {
            values = result.values;
            revision = result.revision;
            status = "ok";
            recoverable = result.canRestore === true;
            if (result.status === "applied") draft = null;
            issue = draft ? qsTr("Review the saved values, then retry or discard your change.") : "";
        } else if (result?.status === "conflict") {
            status = "loading";
            refreshQueued = true;
        } else if (result?.status === "busy") {
            issue = qsTr("Preferences are being changed by another process. Retry when it finishes.");
        } else {
            status = "invalid";
            revision = result?.revision || "";
            recoverable = result?.canRestore === true;
            issue = !result ? qsTr("Could not read the Settings preferences.")
                : result.reason === "unsupported_version" ? qsTr("These preferences were saved by a newer version.")
                : qsTr("The preferences could not be read or saved. The last valid values are still in use.");
            if (operation !== "read") refreshQueued = true;
        }
        if (refreshQueued && watching) {
            refreshQueued = false;
            refreshTimer.restart();
        }
    }

    property FileView watcher: FileView {
        path: root.path
        preload: false
        printErrors: false
        watchChanges: root.watching
        onFileChanged: refreshTimer.restart()
    }

    property Timer refreshTimeout: Timer {
        id: refreshTimer
        interval: 110
        onTriggered: if (root.watching) root.refresh()
    }

    property Timer operationTimeout: Timer {
        id: failTimer
        interval: 2600
        onTriggered: {
            runner.running = false;
            root.complete(null);
        }
    }

    property Process process: Process {
        id: runner
        stdinEnabled: true
        onStarted: if (root.request) write(JSON.stringify(root.request) + "\n")
        stdout: StdioCollector { id: response }
        onExited: code => {
            let result = null;
            try {
                if (code === 0) result = JSON.parse(response.text);
            } catch (error) {}
            root.complete(result);
        }
    }
}
