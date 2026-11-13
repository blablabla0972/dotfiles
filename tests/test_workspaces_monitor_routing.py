"""Exercise workspace selection against simulated per-monitor Hyprland state."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKSPACES = ROOT / "config/quickshell/rice-shell/bar/Workspaces.qml"


@unittest.skipUnless(shutil.which("qml6"), "qml6 required")
class WorkspacesMonitorRoutingTest(unittest.TestCase):
    def test_click_scroll_special_workspace_and_monitor_hotplug(self):
        source = WORKSPACES.read_text()
        self.assertIn("required property var targetMonitor", source)
        self.assertIn("required property var workspaceList", source)
        self.assertIn("function activateWorkspace", source)
        self.assertIn("function cycleWorkspace", source)

        with tempfile.TemporaryDirectory(prefix="rice-workspaces-") as directory:
            base = Path(directory)
            (base / "bar").mkdir()
            (base / "theme").mkdir()
            shutil.copyfile(WORKSPACES, base / "bar/Workspaces.qml")
            (base / "theme/qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (base / "theme/Tokens.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property color accent: "#80aaff"; property color outline: "#505060" }
''')
            main = base / "main.qml"
            main.write_text('''import QtQuick
import QtQuick.Window
import "./bar"
Window {
    id: root
    visible: true; width: 500; height: 80
    QtObject { id: monitorA; property string name: "A"; property var activeWorkspace: wsA3 }
    QtObject { id: monitorB; property string name: "B"; property var activeWorkspace: wsB4 }
    QtObject { id: wsA1; property int id: 1; property var monitor: monitorA; property var lastIpcObject: ({windows: 1}); property int activations: 0; function activate() { activations++; } }
    QtObject { id: wsA3; property int id: 3; property var monitor: monitorA; property var lastIpcObject: ({windows: 0}); property int activations: 0; function activate() { activations++; } }
    QtObject { id: wsA5; property int id: 5; property var monitor: monitorA; property var lastIpcObject: ({windows: 2}); property int activations: 0; function activate() { activations++; } }
    QtObject { id: wsB2; property int id: 2; property var monitor: monitorB; property var lastIpcObject: ({windows: 0}); property int activations: 0; function activate() { activations++; } }
    QtObject { id: wsB4; property int id: 4; property var monitor: monitorB; property var lastIpcObject: ({windows: 1}); property int activations: 0; function activate() { activations++; } }
    QtObject { id: special; property int id: -99; property var monitor: monitorA; property var lastIpcObject: ({windows: 1}); function activate() {} }
    Workspaces {
        id: bar
        anchors.centerIn: parent
        targetMonitor: monitorA
        workspaceList: [wsA1, wsA3, wsA5, wsB2, wsB4, special]
    }
    Timer {
        interval: 50; running: true; repeat: false
        onTriggered: {
            const idsA = bar.workspaceItems.map(workspace => workspace.id);
            if (JSON.stringify(idsA) !== "[1,3,5]") throw new Error("wrong monitor A set: " + idsA);
            if (bar.workspaceItems[1].lastIpcObject.windows !== 0) throw new Error("workspace occupancy missing");
            bar.activateWorkspace(bar.workspaceItems[1]);
            if (wsA3.activations !== 1 || wsB2.activations !== 0) throw new Error("click crossed monitors");
            bar.cycleWorkspace(1);
            if (wsA5.activations !== 1) throw new Error("scroll did not cycle on monitor A");
            monitorA.activeWorkspace = wsA5;
            bar.cycleWorkspace(-1);
            if (wsA3.activations !== 2) throw new Error("reverse scroll targeted the wrong workspace");
            bar.targetMonitor = monitorB;
            const idsB = bar.workspaceItems.map(workspace => workspace.id);
            if (JSON.stringify(idsB) !== "[2,4]") throw new Error("hotplug target retained stale workspaces: " + idsB);
            bar.activateWorkspace(wsA1);
            bar.cycleWorkspace(1);
            if (wsA1.activations !== 0 || wsB2.activations !== 1) throw new Error("monitor B routing failed");
            bar.targetMonitor = null;
            bar.cycleWorkspace(1);
            if (wsB2.activations !== 1) throw new Error("missing monitor must be a no-op");
            console.log("WORKSPACE_RESULT:" + JSON.stringify({idsA, idsB, a1: wsA1.activations,
                a3: wsA3.activations, a5: wsA5.activations, b2: wsB2.activations, b4: wsB4.activations}));
            Qt.exit(73);
        }
    }
}
''')
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
            result = subprocess.run(["qml6", "-f", str(main), "--quit-after", "2000"],
                                    env=env, capture_output=True, text=True, timeout=4)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
