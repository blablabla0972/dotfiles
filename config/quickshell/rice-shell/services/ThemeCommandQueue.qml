pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQml
import "../theme"

QtObject {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string themeScript: configHome + "/hypr/scripts/generate-theme.py"
    property var pendingCommands: []
    property string result: ""
    property bool reloadPending: false
    readonly property bool running: process.running || confirmation.running
    readonly property int pendingCount: pendingCommands.length

    property int nextThemeRequest: 0
    property var current: null
    signal reloadRequested()
    signal themeModeFinished(int requestId, string outcome, string actualMode)

    property Timer confirmation: Timer {
        interval: 1500
        onTriggered: root.finishMode("unconfirmed")
    }

    property Connections modeChanges: Connections {
        target: Tokens
        function onParsedDataChanged(): void { root.confirmMode(); }
    }

    function requestThemeMode(mode: string, expectedMode: string): int {
        if ((mode !== "dark" && mode !== "light") || mode === expectedMode
                || !Tokens.isValid || Tokens.mode !== expectedMode) return 0;
        const id = ++nextThemeRequest;
        enqueue(["python3", themeScript, "--theme-mode-changed", "--mode", mode],
            { id: id, mode: mode, expectedMode: expectedMode });
        return id;
    }

    function confirmMode(): void {
        if (confirmation.running && Tokens.isValid && Tokens.mode === current.ticket.mode)
            finishMode("applied");
    }

    function finishMode(outcome: string): void {
        confirmation.stop();
        const id = current.ticket.id;
        current = null;
        result = outcome === "applied" ? "Command completed" : "Theme change " + outcome;
        themeModeFinished(id, outcome, Tokens.isValid ? Tokens.mode : "");
        Qt.callLater(root.startNextCommand);
    }

    property var process: Process {
        onRunningChanged: {
            if (!running) Qt.callLater(root.commandStopped);
        }
        onExited: (exitCode) => {
            if (root.current && root.current.ticket) {
                if (exitCode !== 0) root.finishMode("failed");
                else {
                    root.confirmation.start();
                    Tokens.reloadTheme();
                    root.confirmMode();
                }
                return;
            }
            root.current = null;
            root.result = exitCode === 0
                ? "Command completed"
                : "Command failed (exit " + exitCode + ")";
        }
    }

    function commandStopped(): void {
        if (running) return;
        if (current && current.ticket) {
            finishMode("failed");
            return;
        }
        if (current) {
            current = null;
            result = "Command did not start";
        }
        startNextCommand();
    }

    function isThemeCommand(command: var): bool {
        if (!command || command.length < 2 || typeof command[1] !== "string") return false;
        return command[1].substring(command[1].lastIndexOf("/") + 1) === "generate-theme.py";
    }

    function queueCommand(command: var): void {
        if (!Array.isArray(command) || command.length === 0) {
            result = "Invalid command";
            return;
        }

        enqueue(command, null);
    }

    function enqueue(command, ticket): void {
        if (isThemeCommand(command)) {
            var retained = [];
            for (var i = 0; i < pendingCommands.length; i++) {
                const request = pendingCommands[i];
                if (!isThemeCommand(request.command)) retained.push(request);
                else if (request.ticket) {
                    const id = request.ticket.id;
                    Qt.callLater(() => root.themeModeFinished(id, "superseded", Tokens.isValid ? Tokens.mode : ""));
                }
            }
            pendingCommands = retained;
        }
        pendingCommands = pendingCommands.concat([{ command: command.slice(), ticket: ticket }]);
        if (!running) startNextCommand();
    }

    function startNextCommand(): void {
        if (running || current || confirmation.running) return;
        if (pendingCommands.length > 0) {
            var next = pendingCommands[0];
            pendingCommands = pendingCommands.slice(1);
            current = next;
            if (next.ticket && (!Tokens.isValid || Tokens.mode !== next.ticket.expectedMode)) {
                const id = next.ticket.id;
                current = null;
                Qt.callLater(() => {
                    root.themeModeFinished(id, "conflict", Tokens.isValid ? Tokens.mode : "");
                    root.startNextCommand();
                });
                return;
            }
            process.command = next.command;
            result = "";
            process.running = true;
            return;
        }
        if (reloadPending) {
            reloadPending = false;
            result = "Reloading Rice Shell";
            Qt.callLater(() => root.reloadRequested());
        }
    }

    function switchTheme(mode: string): void {
        if (mode !== "dark" && mode !== "light") {
            result = "Invalid theme mode";
            return;
        }
        queueCommand(["python3", themeScript, "--theme-mode-changed", "--mode", mode]);
    }

    function regenerateTheme(): void {
        queueCommand(["python3", themeScript, "--wallpaper-changed"]);
    }

    function reloadHyprland(): void {
        queueCommand(["hyprctl", "reload"]);
    }

    function requestShellReload(): void {
        if (!running && !current && pendingCommands.length === 0) {
            reloadRequested();
            return;
        }
        reloadPending = true;
        result = "Shell reload waits for queued commands";
    }
}
