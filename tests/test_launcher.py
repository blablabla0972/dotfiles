"""Tests for Quickshell App Launcher and Top Bar Integration."""
from pathlib import Path
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
