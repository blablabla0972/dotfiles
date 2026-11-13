"""Exercise ShellRoot modal dispatch with native QML objects and fake monitors."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_island_monitor_dispatch import extract_qml_block

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/rice-shell/shell.qml"
ISLAND_STATE = ROOT / "config/quickshell/rice-shell/island/IslandState.js"


@unittest.skipUnless(shutil.which("qml6"), "qml6 required")
class ModalOwnershipTest(unittest.TestCase):
    def test_one_interactive_modal_and_explicit_same_target_toggle(self):
        source = SHELL.read_text()
        names = ("instanceOnScreen", "hasInteractiveModal", "dismissOtherModals",
                 "toggleLauncher", "toggleDashboard", "togglePowerMenu", "toggleSideDrawer")
        functions = []
        for name in names:
            marker = f"    function {name}("
            functions.append(extract_qml_block(source, marker))
        functions[0] = functions[0].replace("Hyprland.focusedMonitor", "fakeHyprland.focusedMonitor")

        with tempfile.TemporaryDirectory(prefix="rice-modal-owner-") as directory:
            base = Path(directory)
            shutil.copyfile(ISLAND_STATE, base / "IslandState.js")
            main = base / "main.qml"
            main.write_text('''import QtQuick
import "./IslandState.js" as IslandState
Item {
    id: root
    property var islandInstances: [left, right]
    property var launcherInstances: [launcher]
    property var powerMenuInstances: [power]
    QtObject { id: fakeHyprland; property var focusedMonitor: screenA }
    QtObject { id: screenA; property string name: "A" }
    QtObject { id: screenB; property string name: "B" }
    QtObject {
        id: left
        property var targetScreen: screenA
        property bool dashboardExpanded: false
        property bool isPinned: false
        property string dashboardCurrentTab: "Home"
        property string drawer: ""
        function dismissDashboard() { dashboardExpanded = false; }
        function collapse() { isPinned = false; }
        function toggleDashboard(tab) {
            if (dashboardExpanded && dashboardCurrentTab === tab) dashboardExpanded = false;
            else { dashboardExpanded = true; dashboardCurrentTab = tab; }
        }
        function toggleSideDrawer(type) { drawer = drawer === type ? "" : type; }
    }
    QtObject {
        id: right
        property var targetScreen: screenB
        property bool dashboardExpanded: false
        property bool isPinned: false
        property string dashboardCurrentTab: "Home"
        property string drawer: ""
        function dismissDashboard() { dashboardExpanded = false; }
        function collapse() { isPinned = false; }
        function toggleDashboard(tab) {
            if (dashboardExpanded && dashboardCurrentTab === tab) dashboardExpanded = false;
            else { dashboardExpanded = true; dashboardCurrentTab = tab; }
        }
        function toggleSideDrawer(type) { drawer = drawer === type ? "" : type; }
    }
    QtObject {
        id: launcher
        property var targetScreen: screenA
        property bool visible: false
        function dismiss() { visible = false; }
        function toggle() { visible = !visible; }
    }
    QtObject {
        id: power
        property var targetScreen: screenB
        property bool visible: false
        function dismissMenu() { visible = false; }
        function toggle() { visible = !visible; }
    }
''' + "\n".join(functions) + '''
    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: {
            left.dashboardExpanded = true;
            right.isPinned = true;
            launcher.visible = true;
            root.togglePowerMenu(screenB);
            if (left.dashboardExpanded || right.isPinned || launcher.visible || !power.visible)
                throw new Error("opening Power did not dismiss the other modal owners");
            if (!root.hasInteractiveModal()) throw new Error("Power was not recognized as modal");
            root.togglePowerMenu(screenB);
            if (power.visible) throw new Error("same-target Power toggle did not close");
            root.toggleDashboard("Home", screenA);
            root.toggleDashboard("System", screenA);
            if (!left.dashboardExpanded || left.dashboardCurrentTab !== "System")
                throw new Error("Dashboard tab switch closed or lost the target");
            root.toggleDashboard("System", screenA);
            if (left.dashboardExpanded) throw new Error("same-tab Dashboard toggle did not close");
            power.visible = true;
            root.toggleLauncher(screenA);
            if (power.visible || !launcher.visible) throw new Error("Launcher did not take modal ownership");
            root.toggleLauncher(screenA);
            if (launcher.visible) throw new Error("same-target Launcher toggle did not close");
            root.toggleSideDrawer("wifi", screenB);
            if (!right.dashboardExpanded || right.dashboardCurrentTab !== "Home" || right.drawer !== "wifi")
                throw new Error("drawer did not open on its target monitor");
            root.toggleSideDrawer("wifi", screenB);
            if (right.drawer !== "") throw new Error("same drawer toggle did not close");
            root.toggleSideDrawer("bogus", screenB);
            if (right.drawer !== "" || right.dashboardCurrentTab !== "Home")
                throw new Error("unknown drawer changed dashboard state");
            right.dashboardCurrentTab = "System";
            root.toggleSideDrawer("wifi", screenB);
            if (right.dashboardCurrentTab !== "Home" || right.drawer !== "wifi")
                throw new Error("drawer from System did not route through Home");
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
