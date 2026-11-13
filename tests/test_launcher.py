"""Tests for Quickshell App Launcher and Top Bar Integration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER_QML = ROOT / "config/quickshell/rice-shell/launcher/Launcher.qml"
BAR_QML = ROOT / "config/quickshell/rice-shell/bar/Bar.qml"
SHELL_QML = ROOT / "config/quickshell/rice-shell/shell.qml"
BINDS_LUA = ROOT / "config/hypr/config/binds.lua"


class QuickshellAppLauncherTest(unittest.TestCase):
    def test_launcher_desktop_entries_native_api(self):
        self.assertTrue(LAUNCHER_QML.exists(), "Launcher.qml must exist")
        content = LAUNCHER_QML.read_text()

        # Must use DesktopEntries.applications (native Quickshell singleton)
        self.assertIn("DesktopEntries.applications", content)
        # Must NOT use Quickshell.applications (does not exist in Quickshell 0.3.2)
        self.assertNotIn("Quickshell.applications", content)

    def test_launcher_categories_and_zero_state(self):
        content = LAUNCHER_QML.read_text()

        # Categories
        for cat in ["All", "Internet", "Development", "Multimedia", "System", "Settings"]:
            self.assertIn(f'"{cat}"', content)

        # Zero state method without pinned separation
        self.assertIn("getZeroStateApps()", content)
        self.assertNotIn("isPinnedApp", content)
        self.assertNotIn('text: "Pinned"', content)

    def test_launcher_command_runner(self):
        content = LAUNCHER_QML.read_text()

        # Command runner with '>'
        self.assertIn('query.startsWith(">")', content)
        self.assertIn("executeCommand", content)

    def test_launcher_reset_is_owned_by_visible_transition(self):
        content = LAUNCHER_QML.read_text()
        toggle = content.split("function toggle(): void {", 1)[1].split("function cycleCategory", 1)[0]
        visible_changed = content.split("onVisibleChanged: {", 1)[1].split("// Backdrop Scrim", 1)[0]

        self.assertNotIn("searchText =", toggle)
        self.assertTrue("if (visible)" in visible_changed, "visible transition must guard opening resets")
        for reset in (
            'searchText = "";',
            'selectedCategory = "All";',
            "searchInput.text = \"\";",
            "searchInput.forceActiveFocus();",
            "appList.positionViewAtBeginning()",
            "categoryList.positionViewAtBeginning()",
        ):
            self.assertTrue(reset in visible_changed, f"visible transition must restore {reset}")
        self.assertIn("selectedIndex = filteredApps.length > 0 ? 0 : -1;", visible_changed)

    def test_launcher_zero_state_comment_matches_sorted_apps(self):
        content = LAUNCHER_QML.read_text()

        self.assertTrue(
            "// 2. Zero-state: valid apps in the selected category, sorted alphabetically" in content,
            "zero-state comment must describe the alphabetical app list",
        )
        self.assertFalse(
            "pinned essentials followed by curated list" in content,
            "misleading pinned-curated comment remains",
        )

    def test_launcher_uses_one_detached_execution_path_with_failure_handling(self):
        content = LAUNCHER_QML.read_text()
        execute_command = content.split("function executeCommand(cmd: string): void {", 1)[1].split("function launchSelected()", 1)[0]

        self.assertTrue("Quickshell.execDetached(args)" in execute_command, "use the documented detached API")
        self.assertFalse("Quickshell.execute" in execute_command, "remove the undocumented execute branch")
        self.assertFalse("cmdProcess" in execute_command, "remove the alternate process fallback")
        self.assertTrue(
            'var terminal = (Quickshell.env("TERMINAL") || "").trim() || "kitty";' in execute_command,
            "use a non-empty terminal executable",
        )
        self.assertTrue("catch (e)" in execute_command, "execution errors must be handled")
        self.assertTrue("console.warn" in execute_command, "execution failures must be reported")
        catch_block = execute_command.split("} catch (e) {", 1)[1]
        self.assertFalse("launcherWindow.visible = false" in catch_block, "keep launcher open after execution failure")

    def test_launcher_shell_execution_requires_explicit_command_mode(self):
        content = LAUNCHER_QML.read_text()
        launch_selected = content.split("function launchSelected(): void {", 1)[1].split("onSelectedIndexChanged:", 1)[0]

        self.assertTrue(
            'if (query.startsWith(">")) {\n            executeCommand(query);' in launch_selected,
            "shell execution must remain behind explicit > command mode",
        )
        self.assertTrue(
            'else if (typeof item.execute === "function") {' in launch_selected,
            "app results must use DesktopEntry.execute",
        )
        self.assertNotIn("executeCommand(item.name)", launch_selected)

    def test_launcher_does_not_execute_commands_when_opened(self):
        content = LAUNCHER_QML.read_text()
        visible_changed = content.split("onVisibleChanged: {", 1)[1].split("// Backdrop Scrim", 1)[0]

        self.assertFalse("launchSelected()" in visible_changed, "opening the launcher must not activate a result")
        self.assertFalse("executeCommand(" in visible_changed, "opening the launcher must not run a command")
        self.assertTrue("Keys.onReturnPressed" in content, "commands remain explicitly user-triggered")

    def test_launcher_preserves_escape_and_outside_close(self):
        content = LAUNCHER_QML.read_text()
        escape = content.split("Keys.onEscapePressed:", 1)[1].split("Keys.onReturnPressed:", 1)[0]

        self.assertTrue("launcherWindow.visible = false;" in escape, "Escape must dismiss the launcher")
        self.assertTrue("onTapped: launcherWindow.visible = false" in content, "outside click must dismiss the launcher")

    def test_launcher_clamps_selection_when_results_change(self):
        content = LAUNCHER_QML.read_text()
        self.assertTrue("onFilteredAppsChanged:" in content, "results changes must clamp selectedIndex")
        result_change = content.split("onFilteredAppsChanged:", 1)[1].split("onSelectedIndexChanged:", 1)[0]

        self.assertTrue(
            "selectedIndex = filteredApps.length === 0 ? -1 : Math.max(0, Math.min(selectedIndex, filteredApps.length - 1));" in result_change,
            "selectedIndex must be -1 for no results and in range otherwise",
        )

    def test_launcher_has_explicit_dismiss_method(self):
        content = LAUNCHER_QML.read_text()

        self.assertTrue("function dismiss(): void {\n        visible = false;\n    }" in content)

    def test_launcher_offscreen_qml_open_reset_dismiss_focus_lifecycle(self):
        qmlscene = shutil.which("qmlscene6")
        if not qmlscene:
            self.skipTest("qmlscene6 is not installed")

        with tempfile.TemporaryDirectory(prefix="launcher-qml-test-") as tmp:
            root = Path(tmp)
            (root / "stubs").mkdir()
            (root / "launcher").mkdir()
            stubs = {
                "qmldir": """\
                    module LauncherTestStubs
                    singleton Quickshell 1.0 Quickshell.qml
                    singleton DesktopEntries 1.0 DesktopEntries.qml
                    singleton Tokens 1.0 Tokens.qml
                    TestPanelWindow 1.0 TestPanelWindow.qml
                    TestRegion 1.0 TestRegion.qml
                """,
                "Quickshell.qml": """\
                    pragma Singleton
                    import QtQml
                    QtObject {
                        property int executionCount: 0
                        function env(name) { return ""; }
                        function execDetached(args) { executionCount += 1; }
                    }
                """,
                "DesktopEntries.qml": """\
                    pragma Singleton
                    import QtQml
                    QtObject { property var applications: ({ values: [] }) }
                """,
                "Tokens.qml": """\
                    pragma Singleton
                    import QtQuick
                    QtObject {
                        property color accent: "#80aaff"
                        property color outline: "#808080"
                        property real panelOpacity: 1
                        property color surface: "#202020"
                        property color surface_high: "#303030"
                        property color text_primary: "#ffffff"
                        property color text_secondary: "#aaaaaa"
                    }
                """,
                "TestPanelWindow.qml": """\
                    import QtQuick
                    Item {
                        width: 800
                        height: 600
                        property var targetScreen
                        property var screen
                        property color color: "transparent"
                        property int exclusiveZone: 0
                        property var mask
                    }
                """,
                "TestRegion.qml": """\
                    import QtQml
                    QtObject { property var item }
                """,
            }
            for name, source_text in stubs.items():
                (root / "stubs" / name).write_text(textwrap.dedent(source_text))

            source = LAUNCHER_QML.read_text()
            source = source.replace("import Quickshell\n", 'import "../stubs"\n')
            source = source.replace("import Quickshell.Wayland\n", "")
            source = source.replace('import "../theme"\n', "")
            source = source.replace("required property ShellScreen targetScreen", "property var targetScreen")
            source = source.replace("PanelWindow {", "TestPanelWindow {")
            source = source.replace("Region {", "TestRegion {")
            source = source.replace("    WlrLayershell.layer: WlrLayer.Overlay\n", "")
            source = source.replace("    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n", "")
            source = source.replace("""    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

""", "")
            source = source.replace(
                "id: launcherWindow\n",
                "id: launcherWindow\n    property alias harnessSearchInput: searchInput\n",
                1,
            )
            (root / "launcher/Launcher.qml").write_text(source)

            (root / "harness.qml").write_text(textwrap.dedent("""\
                import QtQuick
                import QtQuick.Window
                import "./stubs"
                import "./launcher" as LauncherUnderTest

                Window {
                    id: harness
                    visible: true
                    width: 800
                    height: 600

                    LauncherUnderTest.Launcher {
                        id: launcher
                        anchors.fill: parent
                        targetScreen: null
                    }

                    function verify(base, index) {
                        if (!launcher.visible) { Qt.exit(base); return false; }
                        if (launcher.searchText !== "") { Qt.exit(base + 1); return false; }
                        if (launcher.selectedCategory !== "All") { Qt.exit(base + 2); return false; }
                        if (launcher.selectedIndex !== index) { Qt.exit(base + 3); return false; }
                        if (launcher.harnessSearchInput.text !== "") { Qt.exit(base + 4); return false; }
                        if (!launcher.harnessSearchInput.activeFocus) { Qt.exit(base + 5); return false; }
                        return true;
                    }

                    Timer {
                        id: opened
                        interval: 50
                        running: true
                        onTriggered: {
                            if (!harness.verify(10, -1)) return;
                            launcher.launchSelected();
                            if (Quickshell.executionCount !== 0 || !launcher.visible || launcher.selectedIndex !== -1) { Qt.exit(16); return; }
                            DesktopEntries.applications = ({ values: [{ name: "Harness app", categories: ["System"] }] });
                            results.start();
                        }
                    }

                    Timer {
                        id: results
                        interval: 50
                        onTriggered: {
                            if (launcher.filteredApps.length === 0 || launcher.selectedIndex !== 0) { Qt.exit(17); return; }
                            if (typeof launcher.dismiss !== "function") { Qt.exit(18); return; }
                            launcher.dismiss();
                            if (launcher.visible) { Qt.exit(19); return; }
                            launcher.searchText = "stale";
                            launcher.selectedCategory = "System";
                            launcher.harnessSearchInput.text = "stale";
                            launcher.selectedIndex = 4;
                            launcher.toggle();
                            reopened.start();
                        }
                    }

                    Timer {
                        id: reopened
                        interval: 50
                        onTriggered: {
                            if (!harness.verify(20, 0)) return;
                            launcher.dismiss();
                            Qt.quit();
                        }
                    }

                    Component.onCompleted: {
                        launcher.searchText = "stale";
                        launcher.selectedCategory = "System";
                        launcher.harnessSearchInput.text = "stale";
                        launcher.selectedIndex = 4;
                        launcher.toggle();
                    }
                }
            """))

            env = os.environ.copy()
            env["QT_QPA_PLATFORM"] = "offscreen"
            env["QT_QUICK_BACKEND"] = "software"
            result = subprocess.run(
                [qmlscene, str(root / "harness.qml")],
                cwd=root,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=15,
                check=False,
            )
            failures = {
                10: "open failed",
                11: "search text not reset",
                12: "category not reset",
                13: "selection sentinel incorrect",
                14: "input text not reset",
                15: "input did not gain focus",
                16: "empty launch was not a no-op",
                17: "non-empty selection did not reset to zero",
                18: "dismiss method missing",
                19: "dismiss failed",
                20: "reopen failed",
                21: "search text not reset on reopen",
                22: "category not reset on reopen",
                23: "selection did not reset on reopen",
                24: "input text not reset on reopen",
                25: "input did not regain focus",
            }
            self.assertEqual(result.returncode, 0, failures.get(result.returncode, result.stdout[-1500:]))

    def test_launcher_keyboard_navigation(self):
        content = LAUNCHER_QML.read_text()

        # Essential keyboard handlers
        self.assertIn("Keys.onEscapePressed", content)
        self.assertIn("Keys.onReturnPressed", content)
        self.assertIn("Keys.onDownPressed", content)
        self.assertIn("Keys.onUpPressed", content)
        self.assertIn("Keys.onTabPressed", content)
        self.assertIn("cycleCategory", content)

    def test_launcher_layershell_input_mask(self):
        content = LAUNCHER_QML.read_text()

        # Prevent fullscreen click trapping when closed
        self.assertIn("mask: Region", content)
        self.assertIn("launcherWindow.visible ? scrim : null", content)

    def test_bar_launcher_wiring(self):
        self.assertTrue(BAR_QML.exists(), "Bar.qml must exist")
        bar_content = BAR_QML.read_text()

        # Bar signals
        self.assertIn("signal requestLauncher()", bar_content)
        self.assertIn("signal requestDashboard(string tab)", bar_content)
        self.assertIn("barRoot.requestLauncher()", bar_content)

        # Shell wiring
        shell_content = SHELL_QML.read_text()
        self.assertIn("onRequestLauncher", shell_content)
        self.assertIn("root.toggleLauncher(modelData)", shell_content)
        self.assertIn("root.instanceOnScreen(launcherInstances, screen)", shell_content.replace("instanceOnScreen(launcherInstances, screen)", "root.instanceOnScreen(launcherInstances, screen)"))

    def test_hyprland_binds_hotkeys(self):
        self.assertTrue(BINDS_LUA.exists(), "binds.lua must exist")
        content = BINDS_LUA.read_text()

        self.assertIn("toggleLauncher", content)
        self.assertIn("toggleDashboard", content)


if __name__ == "__main__":
    unittest.main()
