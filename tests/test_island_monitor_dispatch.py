"""Exercise production Island IPC dispatch with two simulated monitors."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/shell.qml"


@unittest.skipUnless(shutil.which("qml6"), "qml6 required")
class IslandMonitorDispatchTest(unittest.TestCase):
    def test_feedback_only_appears_on_focused_monitor(self):
        source = SHELL.read_text()
        instance_fn = source[source.index("    function instanceOnScreen("):
                             source.index("    function toggleLauncher(")]
        feedback_fns = source[source.index("        function islandOsd("):
                              source.index("        function toggleLauncher()")]

        # Replace the external Hyprland singleton with an isolated test object.
        instance_fn = instance_fn.replace("Hyprland.focusedMonitor", "fakeHyprland.focusedMonitor")
        self.assertIn("fakeHyprland.focusedMonitor", instance_fn)
        self.assertEqual(feedback_fns.count("root.instanceOnScreen(islandInstances, null)"), 3)

        harness = """import QtQuick
Item {
    id: root
    property var islandInstances: [left, right]
    QtObject {
        id: fakeHyprland
        property var focusedMonitor: ({ name: "DP-2" })
    }
    QtObject {
        id: left
        property var targetScreen: ({ name: "HDMI-A-1" })
        property int osds: 0
        property int alerts: 0
        function triggerOsd(icon, progress) { osds++; }
        function triggerNotification(summary, body, app, icon) { alerts++; }
    }
    QtObject {
        id: right
        property var targetScreen: ({ name: "DP-2" })
        property int osds: 0
        property int alerts: 0
        function triggerOsd(icon, progress) { osds++; }
        function triggerNotification(summary, body, app, icon) { alerts++; }
    }
""" + instance_fn + """
    QtObject {
        id: riceIpc
""" + feedback_fns + """
    }
    function check(ok, message) {
        if (!ok) { console.error("MONITOR_DISPATCH_FAIL: " + message); Qt.exit(1); throw new Error(message); }
    }
    Component.onCompleted: Qt.callLater(() => {
        riceIpc.islandOsd("brightness", 0.65);
        riceIpc.islandNotify("Error", "details");
        riceIpc.islandNotification("Hello", "body", "app", "icon");
        check(left.osds === 0 && left.alerts === 0, "unfocused monitor received feedback");
        check(right.osds === 1 && right.alerts === 2, "focused monitor missed feedback");

        fakeHyprland.focusedMonitor = { name: "HDMI-A-1" };
        riceIpc.islandOsd("volume", 0.3);
        riceIpc.islandNotification("Hello", "body", "app", "icon");
        check(left.osds === 1 && left.alerts === 1, "focus switch failed");
        check(right.osds === 1 && right.alerts === 2, "previous monitor received feedback");

        fakeHyprland.focusedMonitor = null;
        riceIpc.islandNotify("Fallback", "body");
        check(left.alerts === 2 && right.alerts === 2, "fallback must target one monitor");
        root.islandInstances = [];
        riceIpc.islandOsd("brightness", 0.9);
        riceIpc.islandNotification("None", "body", "app", "icon");
        check(left.osds === 1 && right.osds === 1, "detached monitors received feedback");
        Qt.exit(73);
    });
}
"""
        with tempfile.TemporaryDirectory(prefix="rice-island-monitors-") as tmp:
            path = Path(tmp) / "Main.qml"
            path.write_text(harness)
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
            result = subprocess.run(
                ["qml6", "-f", str(path), "--quit-after", "3000"],
                env=env, capture_output=True, text=True, timeout=6,
            )
            self.assertEqual(result.returncode, 73, (result.stdout + result.stderr)[-2000:])


if __name__ == "__main__":
    unittest.main()
