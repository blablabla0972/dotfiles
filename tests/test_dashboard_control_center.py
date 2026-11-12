"""Tests for Dynamic Island Control Center (Dashboard) and Telemetry."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
TELEMETRY_SCRIPT = ROOT / "config/quickshell/rice-shell/dashboard/telemetry.py"
DASHBOARD_QML = ROOT / "config/quickshell/rice-shell/dashboard/Dashboard.qml"
SYSTEM_QML = ROOT / "config/quickshell/rice-shell/dashboard/System.qml"
CONFIG_QML = ROOT / "config/quickshell/rice-shell/dashboard/Config.qml"
QUICKSETTINGS_QML = ROOT / "config/quickshell/rice-shell/dashboard/QuickSettings.qml"
ISLAND_QML = ROOT / "config/quickshell/rice-shell/island/Island.qml"
ISLAND_SHAPE_QML = ROOT / "config/quickshell/rice-shell/island/IslandShape.qml"
SHELL_QML = ROOT / "config/quickshell/rice-shell/shell.qml"
BAR_QML = ROOT / "config/quickshell/rice-shell/bar/Bar.qml"
WIFI_DRAWER_QML = ROOT / "config/quickshell/rice-shell/dashboard/WifiDrawer.qml"
BT_DRAWER_QML = ROOT / "config/quickshell/rice-shell/dashboard/BluetoothDrawer.qml"


class TelemetryScriptTest(unittest.TestCase):
    def test_telemetry_script_execution(self):
        self.assertTrue(TELEMETRY_SCRIPT.exists(), "telemetry.py must exist")
        res = subprocess.run(
            ["python3", str(TELEMETRY_SCRIPT)],
            capture_output=True,
            text=True,
            timeout=5
        )
        self.assertEqual(res.returncode, 0, f"telemetry.py failed: {res.stderr}")
        data = json.loads(res.stdout)
        
        # Verify required telemetry fields
        required_keys = [
            "cpu_pct", "cpu_load", "cpu_model",
            "ram_used", "ram_total", "ram_pct",
            "disk_used", "disk_total", "disk_pct",
            "uptime"
        ]
        for key in required_keys:
            self.assertIn(key, data, f"Missing key in telemetry: {key}")
            
        # Verify numeric bounds
        self.assertTrue(0 <= data["cpu_pct"] <= 100, f"Invalid cpu_pct: {data['cpu_pct']}")
        self.assertTrue(0 <= data["ram_pct"] <= 100, f"Invalid ram_pct: {data['ram_pct']}")
        self.assertTrue(0 <= data["disk_pct"] <= 100, f"Invalid disk_pct: {data['disk_pct']}")
        self.assertTrue(len(data["uptime"]) > 0, "Uptime string should not be empty")


class DynamicIslandDashboardArchitectureTest(unittest.TestCase):
    def test_dashboard_qml_anchoring_and_shape(self):
        content = DASHBOARD_QML.read_text()
        
        # Top anchoring
        self.assertIn("top: true", content)
        # IslandShape usage
        self.assertIn("IslandShape", content)
        # Dimensions ~760w by ~440h
        self.assertIn("760", content)
        self.assertIn("440", content)
        # LayerShell mask verification
        self.assertIn("mask: Region", content)
        # Outside click and Escape key dismissal
        self.assertIn("Keys.onEscapePressed", content)
        self.assertIn("dismiss()", content)
        # Tab content inclusions
        self.assertIn("Home", content)
        self.assertIn("System", content)
        self.assertIn("Config", content)

    def test_island_integration(self):
        content = ISLAND_QML.read_text()
        # Request dashboard signal
        self.assertIn("signal requestDashboard", content)
        # Tapping island in idle/media state toggles dashboard
        self.assertIn("requestDashboard", content)

        shell_content = SHELL_QML.read_text()
        # Shell forwards onRequestDashboard
        self.assertIn("onRequestDashboard", shell_content)
        self.assertIn("toggleDashboard", shell_content)

    def test_quick_settings_controls(self):
        content = QUICKSETTINGS_QML.read_text()
        # Volume slider
        self.assertIn("volTrack", content)
        self.assertIn("Audio.setVolume", content)
        # Brightness slider
        self.assertIn("brightTrack", content)
        self.assertIn("brightnessctl", content)
        # Toggles
        self.assertIn("Wi-Fi", content)
        self.assertIn("Bluetooth", content)
        self.assertIn("Mute", content)
        self.assertIn("DND", content)

    def test_system_telemetry_view(self):
        content = SYSTEM_QML.read_text()
        # CPU, RAM, Disk, Uptime indicators
        self.assertIn("cpuPct", content)
        self.assertIn("ramPct", content)
        self.assertIn("diskPct", content)
        self.assertIn("uptime", content)
        self.assertIn("telemetry.py", content)

    def test_config_view(self):
        content = CONFIG_QML.read_text()
        # Theme switcher
        self.assertIn("Dark Mode", content)
        self.assertIn("Light Mode", content)
        self.assertIn("--theme-mode-changed", content)
        # Reload shell buttons
        self.assertIn("Reload Rice Shell", content)
        self.assertIn("Reload Hyprland", content)

    def test_inner_clicks_do_not_dismiss(self):
        content = DASHBOARD_QML.read_text()
        # Ensure scrim TapHandler checks bounds and does not dismiss on inner clicks
        self.assertIn("minX = morphContainer.x", content)
        self.assertIn("maxX = morphContainer.x + morphContainer.width", content)
        self.assertIn("p.x < minX || p.x > maxX", content)

    def test_osd_volume_layout_refinements(self):
        content = ISLAND_QML.read_text()
        # Ensure modernized OSD volume layout with badge icon, 8px track, and percentage text
        self.assertIn("islandWindow.osdIcon", content)
        self.assertIn("islandWindow.osdProgress", content)
        self.assertIn("islandWindow.osdProgress * 100", content)

    def test_segmented_bar_islands(self):
        self.assertTrue(BAR_QML.exists(), "Bar.qml must exist")
        content = BAR_QML.read_text()

        # Verify 3 distinct floating island blocks exist
        self.assertIn("id: leftIsland", content)
        self.assertIn("id: centerIsland", content)
        self.assertIn("id: rightIsland", content)

        # Left Island: launcher icon button and workspaces
        self.assertIn("launcherHover", content)
        self.assertIn("barRoot.requestLauncher()", content)
        self.assertIn("Workspaces", content)

        # Center Island: horizontal center anchoring, dynamic island inline (idle & media), dashboard request
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", content)
        self.assertIn("Control Center", content)
        self.assertIn("barRoot.requestDashboard(\"Home\")", content)
        self.assertIn("Media.hasPlayer && Media.isPlaying", content)

        # Right Island: status tray and clock pill
        self.assertIn("StatusTray", content)
        self.assertIn("id: clockPill", content)
        self.assertIn("hh:mm", content)

    def test_dynamic_island_media_capsule(self):
        self.assertTrue(ISLAND_QML.exists(), "Island.qml must exist")
        content = ISLAND_QML.read_text()

        # 3-tier expanded media capsule layout
        self.assertIn("expandedMediaContent", content)
        self.assertIn("visualizerPhase", content)
        self.assertIn("visualizerLevel", content)
        self.assertIn("progressBarTrack", content)
        self.assertIn("Media.setPosition", content)
        self.assertIn("Media.previous", content)
        self.assertIn("Media.togglePlaying", content)
        self.assertIn("Media.next", content)

        # Scrim outside-click and escape dismissal
        self.assertIn("id: scrim", content)
        self.assertIn("Keys.onEscapePressed", content)

        # Bar integration: requestMediaCapsule
        bar_content = BAR_QML.read_text()
        self.assertIn("requestMediaCapsule()", bar_content)

    def test_interactive_network_drawers(self):
        self.assertTrue(WIFI_DRAWER_QML.exists(), "WifiDrawer.qml must exist")
        self.assertTrue(BT_DRAWER_QML.exists(), "BluetoothDrawer.qml must exist")

        wifi_content = WIFI_DRAWER_QML.read_text()
        bt_content = BT_DRAWER_QML.read_text()
        qs_content = QUICKSETTINGS_QML.read_text()

        # Wi-Fi drawer: nmcli dev wifi list, inline password, connect/disconnect
        self.assertIn("nmcli", wifi_content)
        self.assertIn("dev", wifi_content)
        self.assertIn("wifi", wifi_content)
        self.assertIn("passInput", wifi_content)
        self.assertIn("closeRequested", wifi_content)

        # Bluetooth drawer: bluetoothctl, device list, scan toggle, connect/disconnect
        self.assertIn("bluetoothctl", bt_content)
        self.assertIn("devices", bt_content)
        self.assertIn("scan", bt_content)
        self.assertIn("closeRequested", bt_content)

        # QuickSettings integration: right-click expand triggers and drawer overlays
        self.assertIn("wifiDrawerOpen", qs_content)
        self.assertIn("btDrawerOpen", qs_content)
        self.assertIn("WifiDrawer", qs_content)
        self.assertIn("BluetoothDrawer", qs_content)
        self.assertIn("Qt.RightButton", qs_content)
        self.assertIn("requestSideDrawer", qs_content)

        # Dashboard sidecar drawer panel (floating next to control center per user sketch)
        dash_content = DASHBOARD_QML.read_text()
        self.assertIn("sideDrawerContainer", dash_content)
        self.assertIn("activeSideDrawer", dash_content)
        self.assertIn("sideDrawerOpen", dash_content)
        self.assertIn("toggleSideDrawer", dash_content)
        self.assertIn("WifiDrawer", dash_content)
        self.assertIn("BluetoothDrawer", dash_content)


if __name__ == "__main__":
    unittest.main()

