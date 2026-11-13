pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool doNotDisturb: false
    readonly property bool nightLightActive: nightLight.running
    readonly property bool caffeineActive: caffeine.running
    property string lastSummary: "No recent notifications"
    property string lastBody: ""
    property var notificationHistory: []
    property real brightnessLevel: 0.8
    property int pendingBrightnessPercent: -1
    property bool brightnessReadQueued: false
    property bool brightnessOsdPending: false
    signal errorOccurred(string message)
    signal brightnessRefreshed(real level, bool showOsd)

    function recordNotification(summary: string, body: string, appName: string, appIcon: string): void {
        notificationHistory = [{
            summary: summary, body: body, appName: appName, appIcon: appIcon,
            time: Qt.formatTime(new Date(), "hh:mm")
        }].concat(notificationHistory).slice(0, 50);
    }

    function clearNotificationHistory(): void { notificationHistory = []; }

    function refreshBrightness(showOsd: bool): void {
        if (showOsd) brightnessOsdPending = true;
        if (brightnessReader.running || brightnessWriter.running
                || brightnessWriteTimer.running || pendingBrightnessPercent >= 0) {
            brightnessReadQueued = true;
            return;
        }
        brightnessReader.running = true;
    }

    function setBrightness(level: real): void {
        var value = Math.max(0.05, Math.min(1, level));
        brightnessLevel = value;
        pendingBrightnessPercent = Math.round(value * 100);
        brightnessReadQueued = true;
        if (!brightnessWriter.running) brightnessWriteTimer.restart();
    }

    function flushBrightness(): void {
        if (brightnessWriter.running || pendingBrightnessPercent < 0) return;
        var percent = pendingBrightnessPercent;
        pendingBrightnessPercent = -1;
        brightnessWriter.command = ["brightnessctl", "set", percent + "%"];
        brightnessWriter.running = true;
    }

    property Timer brightnessWriteTimer: Timer {
        interval: 70
        repeat: false
        onTriggered: root.flushBrightness()
    }

    property Process brightnessWriter: Process {
        onRunningChanged: {
            if (running) return;
            if (root.pendingBrightnessPercent >= 0) root.brightnessWriteTimer.restart();
            else if (root.brightnessReadQueued) {
                root.brightnessReadQueued = false;
                root.refreshBrightness(false);
            }
        }
    }

    property Process brightnessReader: Process {
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                var match = text.match(/(?:^|,)(\d+(?:\.\d+)?)%/);
                if (!match || root.brightnessReadQueued) return;
                var value = Math.max(0, Math.min(1, Number(match[1]) / 100));
                root.brightnessLevel = value;
                root.brightnessRefreshed(value, root.brightnessOsdPending);
                root.brightnessOsdPending = false;
            }
        }
        onRunningChanged: {
            if (!running && root.brightnessReadQueued) {
                root.brightnessReadQueued = false;
                root.refreshBrightness(false);
            }
        }
    }

    function toggleNightLight(): void { nightLight.running = !nightLight.running; }
    function toggleCaffeine(): void { caffeine.running = !caffeine.running; }

    property Process nightLight: Process {
        command: ["gammastep", "-m", "wayland", "-l", "0:0", "-t", "4000:4000", "-r"]
        onExited: (code) => { if (code !== 0) root.errorOccurred("Night Light could not start."); }
    }

    property Process caffeine: Process {
        command: ["systemd-inhibit", "--what=idle:sleep", "--mode=block",
                  "--who=Rice Awake", "--why=Awake enabled in Control Center", "sleep", "infinity"]
        onExited: (code) => { if (code !== 0) root.errorOccurred("Awake could not start."); }
    }
}
