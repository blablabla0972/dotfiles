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


if __name__ == "__main__":
    unittest.main()
