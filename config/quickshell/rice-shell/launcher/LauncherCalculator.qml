pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "QuickActions.js" as QuickActions

Item {
    id: calc
    visible: false

    property bool active: false
    property string expression: ""
    property var result: ({error: "Enter an expression"})
    property int revision: 0
    property int runningRevision: -1
    property bool queued: false
    property bool available: true
    property bool outputLimit: false

    onActiveChanged: schedule()
    onExpressionChanged: schedule()
    Component.onCompleted: schedule()

    function schedule(): void {
        revision++;
        queued = false;
        debounce.stop();
        const input = expression.trim();
        if (!active || !input) {
            result = {error: "Enter an expression"};
            if (backend.running) backend.signal(9);
        }
        else if (input.length > 512) result = {error: "Expression is too long"};
        else if (/[\x00-\x1f\x7f"'`;]/.test(input) || /\b(?:command|plot|load|export|function)\b/i.test(input))
            result = {error: "Unsupported expression"};
        else if (/[+*/^=,(\-]$/.test(input))
            result = {error: "Keep typing..."};
        else {
            const simple = QuickActions.calculate(input);
            if (simple.error === "Cannot divide by zero" || !available) {
                result = simple;
            } else {
                result = {error: "Calculating..."};
                debounce.restart();
            }
        }
    }

    function start(): void {
        if (!queued || backend.running || runningRevision !== -1) return;
        queued = false;
        if (!available) {
            result = QuickActions.calculate(expression);
            return;
        }
        runningRevision = revision;
        outputLimit = false;
        backend.command = ["qalc", "-defaults", "-set", "upxrates 0", "+u8",
                           "-terse", "-time", "350", "--", expression.trim()];
        backend.running = true;
        deadline.restart();
        Qt.callLater(checkStart);
    }

    function checkStart(): void {
        if (runningRevision === -1 || backend.running) return;
        available = false;
        finish(-1);
    }

    function finish(code: int): void {
        if (runningRevision === -1) return;
        deadline.stop();
        if (runningRevision === revision && active) {
            const value = output.text.trim();
            if (!available) result = QuickActions.calculate(expression);
            else if (outputLimit || value.length > 8192) result = {error: "Result is too long"};
            else if (code !== 0 || !value || /^(?:aborted|timed out|undefined|[+-]?(?:nan|inf(?:inity)?|\u221e))$/i.test(value))
                result = {error: code === 9 ? "Calculation timed out" : "Could not evaluate expression"};
            else result = {value, display: value.replace(/\n/g, " ")};
        }
        runningRevision = -1;
        Qt.callLater(start);
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: {
            calc.queued = true;
            calc.start();
        }
    }

    Timer {
        id: deadline
        interval: 1200
        onTriggered: backend.signal(9)
    }

    Process {
        id: backend
        environment: ({XDG_DATA_HOME: "/dev/null", XDG_CONFIG_HOME: "/dev/null", XDG_CACHE_HOME: "/dev/null"})
        stdout: StdioCollector {
            id: output
            waitForEnd: false
            onDataChanged: {
                if (data.byteLength > 8192 && backend.running && !calc.outputLimit) {
                    calc.outputLimit = true;
                    backend.signal(9);
                }
            }
        }
        onExited: (code, status) => calc.finish(status === 0 ? code : 9)
        onRunningChanged: if (!running) Qt.callLater(calc.checkStart)
    }
}
