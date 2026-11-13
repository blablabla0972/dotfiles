pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQml

QtObject {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string themeScript: configHome + "/hypr/scripts/generate-theme.py"
    property var pendingCommands: []
    property string result: ""
    property bool reloadPending: false
    readonly property bool running: process.running
    readonly property int pendingCount: pendingCommands.length

    signal reloadRequested()

    property var process: Process {
        onRunningChanged: {
            if (!running) Qt.callLater(root.startNextCommand);
        }
        onExited: (exitCode) => {
            root.result = exitCode === 0
                ? "Command completed"
                : "Command failed (exit " + exitCode + ")";
        }
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

        if (isThemeCommand(command)) {
            var retained = [];
            for (var i = 0; i < pendingCommands.length; i++) {
                if (!isThemeCommand(pendingCommands[i])) retained.push(pendingCommands[i]);
            }
            pendingCommands = retained;
        }
        pendingCommands = pendingCommands.concat([command.slice()]);
        if (!running) startNextCommand();
    }

    function startNextCommand(): void {
        if (running) return;
        if (pendingCommands.length > 0) {
            var next = pendingCommands[0];
            pendingCommands = pendingCommands.slice(1);
            process.command = next;
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
        if (!running && pendingCommands.length === 0) {
            reloadRequested();
            return;
        }
        reloadPending = true;
        result = "Shell reload waits for queued commands";
    }
}
