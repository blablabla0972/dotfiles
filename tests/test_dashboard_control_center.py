"""Tests for Dynamic Island Control Center (Dashboard) and Telemetry."""
import importlib.util
from io import StringIO
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import select
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
TELEMETRY_SCRIPT = ROOT / "config/quickshell/rice-shell/dashboard/telemetry.py"
DASHBOARD_QML = ROOT / "config/quickshell/rice-shell/dashboard/Dashboard.qml"
SYSTEM_QML = ROOT / "config/quickshell/rice-shell/dashboard/System.qml"
CONFIG_QML = ROOT / "config/quickshell/rice-shell/dashboard/Config.qml"
QUICKSETTINGS_QML = ROOT / "config/quickshell/rice-shell/dashboard/QuickSettings.qml"
MEDIA_QML = ROOT / "config/quickshell/rice-shell/services/Media.qml"
DESKTOP_CONTROLS_QML = ROOT / "config/quickshell/rice-shell/services/DesktopControls.qml"
THEME_COMMAND_QUEUE_QML = ROOT / "config/quickshell/rice-shell/services/ThemeCommandQueue.qml"
ISLAND_QML = ROOT / "config/quickshell/rice-shell/island/Island.qml"
ISLAND_SHAPE_QML = ROOT / "config/quickshell/rice-shell/island/IslandShape.qml"
ISLAND_STATE_JS = ROOT / "config/quickshell/rice-shell/island/IslandState.js"
SHELL_QML = ROOT / "config/quickshell/rice-shell/shell.qml"
BAR_QML = ROOT / "config/quickshell/rice-shell/bar/Bar.qml"
CONNECTIVITY_CENTER_QML = ROOT / "config/quickshell/rice-shell/dashboard/ConnectivityCenter.qml"
NOTIFICATION_CENTER_QML = ROOT / "config/quickshell/rice-shell/dashboard/NotificationCenter.qml"
QUICKSETTING_TILE_QML = ROOT / "config/quickshell/rice-shell/dashboard/QuickSettingTile.qml"
QUICKSETTING_SLIDER_QML = ROOT / "config/quickshell/rice-shell/dashboard/QuickSettingSlider.qml"
WIFI_DRAWER_QML = ROOT / "config/quickshell/rice-shell/dashboard/WifiDrawer.qml"
BT_DRAWER_QML = ROOT / "config/quickshell/rice-shell/dashboard/BluetoothDrawer.qml"


class TelemetryScriptTest(unittest.TestCase):
    def test_missing_resources_are_reported_as_unavailable(self):
        spec = importlib.util.spec_from_file_location("rice_telemetry_missing", TELEMETRY_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        for meminfo in ("", "MemTotal: 0 kB\nMemAvailable: 0 kB\n", "MemTotal: 1024 kB\n"):
            with self.subTest(meminfo=meminfo):
                def fake_open(path, *args, **kwargs):
                    if path == "/proc/meminfo":
                        return StringIO(meminfo)
                    raise OSError("missing proc data")

                zero_capacity = SimpleNamespace(f_blocks=0, f_frsize=4096, f_bfree=0, f_bavail=0)
                with patch("builtins.open", side_effect=fake_open), \
                        patch.object(module, "cpu_times", return_value=(100, 50)), \
                        patch.object(module.time, "sleep"), \
                        patch.object(module.os, "statvfs", return_value=zero_capacity):
                    data = module.get_telemetry()

                self.assertIsNone(data["uptime"])
                self.assertIsNone(data["ram_pct"])
                self.assertIsNone(data["disk_pct"])
                self.assertIsNone(data["disk_used"])
                self.assertIsNone(data["disk_total"])
                json.dumps(data, allow_nan=False)

    def test_native_system_view_marks_stalled_stream_stale(self):
        shell_dir = SYSTEM_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-system-stale-test-") as directory:
            isolated = Path(directory)
            for relative in ("dashboard/System.qml", "theme/Tokens.qml", "theme/qmldir"):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)
            system_path = isolated / "dashboard/System.qml"
            source = system_path.read_text()
            self.assertEqual(source.count("interval: 12000"), 1)
            system_path.write_text(source.replace("interval: 12000", "interval: 500"))
            (isolated / "dashboard/telemetry.py").write_text(
                'import json, time\n'
                'print(json.dumps({"cpu_pct": 23, "ram_pct": 40, "disk_pct": 50, "uptime": "1h", "hostname": "stub"}), flush=True)\n'
                'time.sleep(3)\n'
            )
            (isolated / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 800; height: 480; visible: true
        System { id: system; visible: true }
    }
    Timer {
        interval: 350; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy) console.error("SYSTEM_STALE_FAIL: initial sample missing");
        }
    }
    Timer {
        interval: 1300; running: true; repeat: false
        onTriggered: {
            if (system.sampleHealthy) console.error("SYSTEM_STALE_FAIL: hung stream still shown live");
            else console.log("SYSTEM_STALE_PASS");
            Qt.quit();
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")
            try:
                result = subprocess.run(
                    ["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                    capture_output=True, text=True, timeout=5, env=env,
                )
            except FileNotFoundError:
                self.skipTest("quickshell binary unavailable")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-1300:])
        self.assertNotIn("SYSTEM_STALE_FAIL", output, output[-1300:])
        self.assertIn("SYSTEM_STALE_PASS", output, output[-1300:])

    def test_native_system_view_recovers_after_exit_and_keeps_partial_snapshot_live(self):
        shell_dir = SYSTEM_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-system-recovery-test-") as directory:
            isolated = Path(directory)
            for relative in (
                "dashboard/System.qml", "theme/Tokens.qml", "theme/qmldir",
            ):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)
            system_path = isolated / "dashboard/System.qml"
            source = system_path.read_text()
            self.assertEqual(source.count("interval: 1500"), 1)
            # Exercise the real restart cadence rather than a shortened timer.
            (isolated / "dashboard/telemetry.py").write_text(
                'import json, os, pathlib, time\n'
                'marker = pathlib.Path(os.environ["RICE_TEST_RUN_MARKER"])\n'
                'first = not marker.exists()\n'
                'marker.write_text("started")\n'
                'data = {"cpu_pct": None if first else 42, "ram_pct": None if first else 40, "disk_pct": None if first else 50, "uptime": None if first else "1h", "hostname": "stub"}\n'
                'print(json.dumps(data), flush=True)\n'
                'time.sleep(0.6 if first else 3)\n'
            )
            (isolated / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 800; height: 480; visible: true
        System { id: system; visible: true }
    }
    Timer {
        interval: 300; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy || system.cpuAvailable || system.ramPct !== null || system.diskPct !== null)
                console.error("SYSTEM_RECOVERY_FAIL: partial snapshot marked stale or unavailable metrics became values");
            else console.log("SYSTEM_PARTIAL_PASS");
        }
    }
    Timer {
        interval: 2900; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy || !system.cpuAvailable || system.cpuPct !== 42)
                console.error("SYSTEM_RECOVERY_FAIL: process did not restart with a fresh CPU sample");
            else console.log("SYSTEM_RECOVERY_PASS");
            Qt.quit();
        }
    }
}
''')
            env = dict(
                os.environ,
                QT_QPA_PLATFORM="offscreen",
                QSG_RHI_BACKEND="software",
                RICE_TEST_RUN_MARKER=str(isolated / "run-marker"),
            )
            try:
                result = subprocess.run(
                    ["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                    capture_output=True, text=True, timeout=6, env=env,
                )
            except FileNotFoundError:
                self.skipTest("quickshell binary unavailable")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-1500:])
        self.assertNotIn("SYSTEM_RECOVERY_FAIL", output, output[-1500:])
        self.assertIn("SYSTEM_PARTIAL_PASS", output, output[-1500:])
        self.assertIn("SYSTEM_RECOVERY_PASS", output, output[-1500:])

    def test_native_system_recovers_from_corrupt_telemetry(self):
        shell_dir = SYSTEM_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-system-bad-json-test-") as directory:
            isolated = Path(directory)
            for relative in ("dashboard/System.qml", "theme/Tokens.qml", "theme/qmldir"):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)
            system_path = isolated / "dashboard/System.qml"
            source = system_path.read_text()
            self.assertIn("interval: 12000", source)
            self.assertIn("interval: 1500", source)
            system_path.write_text(source.replace("interval: 12000", "interval: 400")
                                   .replace("interval: 1500", "interval: 200"))
            (isolated / "dashboard/telemetry.py").write_text(
                'import json, os, pathlib, time\n'
                'marker = pathlib.Path(os.environ["RICE_TEST_RUN_MARKER"])\n'
                'first = not marker.exists()\n'
                'marker.write_text("started")\n'
                'if first:\n'
                '    for _ in range(30): print("corrupt-json", flush=True); time.sleep(.08)\n'
                'else:\n'
                '    print(json.dumps({"cpu_pct": 61, "ram_pct": 40, "disk_pct": 50, "uptime": "1h", "hostname": "stub"}), flush=True)\n'
                '    time.sleep(3)\n'
            )
            (isolated / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 800; height: 480; visible: true
        System { id: system; visible: true }
    }
    Timer {
        interval: 2000; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy || system.cpuPct !== 61)
                console.error("SYSTEM_CORRUPT_FAIL: malformed stream suppressed recovery; healthy=" + system.sampleHealthy + " cpu=" + system.cpuPct);
            else console.log("SYSTEM_CORRUPT_PASS");
            Qt.quit();
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software",
                       RICE_TEST_RUN_MARKER=str(isolated / "run-marker"))
            result = subprocess.run(["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                                    capture_output=True, text=True, timeout=6, env=env)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-1200:])
        self.assertNotIn("SYSTEM_CORRUPT_FAIL", output, output[-1200:])
        self.assertIn("SYSTEM_CORRUPT_PASS", output, output[-1200:])

    def test_native_system_view_streams_and_stops_when_hidden(self):
        shell_dir = SYSTEM_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-system-qml-test-") as directory:
            isolated = Path(directory)
            for relative in (
                "dashboard/System.qml", "dashboard/telemetry.py",
                "theme/Tokens.qml", "theme/qmldir",
            ):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)
            (isolated / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 800; height: 480; visible: true
        System { id: system; visible: true }
    }
    Timer {
        interval: 900; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy) console.error("SYSTEM_NATIVE_FAIL: no sample");
            if (system.layoutColumns !== 2 || system.implicitHeight !== 370)
                console.error("SYSTEM_LAYOUT_FAIL: normal viewport did not retain two columns");
            system.width = 680;
            if (system.layoutColumns !== 1 || system.implicitHeight !== 600)
                console.error("SYSTEM_LAYOUT_FAIL: narrow viewport did not stack and grow");
            system.width = 724;
            if (system.layoutColumns !== 2 || system.implicitHeight !== 370)
                console.error("SYSTEM_LAYOUT_FAIL: restored viewport did not return to normal");
            system.visible = false;
        }
    }
    Timer {
        interval: 1200; running: true; repeat: false
        onTriggered: {
            if (system.sampleHealthy) console.error("SYSTEM_NATIVE_FAIL: hidden process active");
            if (system.cpuHistory.length !== 0) console.error("SYSTEM_NATIVE_FAIL: hidden CPU history retained");
            system.visible = true;
        }
    }
    Timer {
        interval: 2100; running: true; repeat: false
        onTriggered: {
            if (!system.sampleHealthy) console.error("SYSTEM_NATIVE_FAIL: restart did not sample");
            else console.log("SYSTEM_NATIVE_PASS");
            Qt.quit();
        }
    }
}
''', encoding="utf-8")
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")
            try:
                result = subprocess.run(
                    ["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                    capture_output=True, text=True, timeout=8, env=env,
                )
            except FileNotFoundError:
                self.skipTest("quickshell binary unavailable")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-1300:])
        self.assertNotIn("SYSTEM_NATIVE_FAIL", output, output[-1300:])
        self.assertNotIn("SYSTEM_LAYOUT_FAIL", output, output[-1300:])
        self.assertIn("SYSTEM_NATIVE_PASS", output, output[-1300:])

    def test_config_stacks_at_narrow_width_and_restores(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-config-responsive-") as directory:
            isolated = Path(directory)
            for folder in ("dashboard", "theme", "services"):
                (isolated / folder).mkdir()
            shutil.copyfile(CONFIG_QML, isolated / "dashboard/Config.qml")
            (isolated / "theme/qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (isolated / "theme/Tokens.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property color accent: "#78baff"
    property color danger: "#ff6677"
    property color on_accent: "#101010"
    property color outline: "#667080"
    property color surface: "#20242b"
    property color surface_high: "#303641"
    property color text_primary: "#ffffff"
    property color text_secondary: "#b9c1ce"
    property string mode: "dark"
    function reloadTheme() {}
}
''')
            (isolated / "services/qmldir").write_text(
                "singleton ThemeCommandQueue 1.0 ThemeCommandQueue.qml\n")
            (isolated / "services/ThemeCommandQueue.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property string result: ""
    property bool running: false
    property int pendingCount: 0
    function queueCommand(command) {}
    function switchTheme(mode) {}
    function regenerateTheme() {}
    function requestShellReload() {}
    function reloadHyprland() {}
}
''')
            (isolated / "shell.qml").write_text('''import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 760; height: 720; visible: true
        Config { id: config; width: 724; height: 370 }
    }
    Timer {
        interval: 120; running: true; repeat: false
        onTriggered: {
            if (config.layoutColumns !== 2 || config.implicitHeight !== 370)
                console.error("CONFIG_LAYOUT_FAIL: normal viewport mismatch");
            config.width = 680;
            if (config.layoutColumns !== 1 || config.implicitHeight !== 700)
                console.error("CONFIG_LAYOUT_FAIL: narrow viewport mismatch");
            config.width = 724;
            if (config.layoutColumns !== 2 || config.implicitHeight !== 370)
                console.error("CONFIG_LAYOUT_FAIL: restored viewport mismatch");
            else console.log("CONFIG_LAYOUT_PASS");
            Qt.quit();
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software",
                       XDG_RUNTIME_DIR=str(isolated / "runtime"), XDG_CONFIG_HOME=str(isolated / "config"))
            (isolated / "runtime").mkdir()
            result = subprocess.run(
                ["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                capture_output=True, text=True, timeout=6, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1400:])
            self.assertNotIn("CONFIG_LAYOUT_FAIL", output, output[-1400:])
            self.assertIn("CONFIG_LAYOUT_PASS", output, output[-1400:])

    def test_watch_mode_streams_without_restarting_and_exits_on_stop(self):
        process = subprocess.Popen(
            ["python3", str(TELEMETRY_SCRIPT), "--watch", "0.35"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            bufsize=1,
        )
        try:
            lines = []
            for _ in range(2):
                readable, _, _ = select.select([process.stdout], [], [], 3.0)
                self.assertTrue(readable, "Watch mode did not stream a snapshot")
                lines.append(json.loads(process.stdout.readline()))
            self.assertEqual(process.poll(), None, "Watch process unexpectedly exited")
            for snapshot in lines:
                self.assertIn("cpu_pct", snapshot)
                self.assertIn("hostname", snapshot)
        finally:
            process.terminate()
            process.communicate(timeout=3)
        self.assertIsNotNone(process.returncode)

    def test_cpu_usage_uses_cpu_time_deltas(self):
        spec = importlib.util.spec_from_file_location("rice_telemetry", TELEMETRY_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        # user, nice, system, idle, iowait, irq, softirq, steal.
        self.assertEqual(module.cpu_usage((1000, 600), (1200, 700)), 50)
        self.assertEqual(module.cpu_usage((1000, 600), (1100, 700)), 0)
        self.assertEqual(module.cpu_usage((1000, 600), (1100, 600)), 100)
        self.assertIsNone(module.cpu_usage((1000, 600), (1000, 600)))

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
            
        for key in ("hostname", "os_name", "kernel", "cpu_threads", "ram_available", "disk_free", "filesystem", "load_1m"):
            self.assertIn(key, data)
        self.assertGreater(data["cpu_threads"], 0)
        self.assertTrue(data["hostname"])
        self.assertTrue(data["kernel"])

        # Verify numeric bounds
        self.assertTrue(data["cpu_pct"] is None or 0 <= data["cpu_pct"] <= 100,
                        f"Invalid cpu_pct: {data['cpu_pct']}")
        self.assertTrue(0 <= data["ram_pct"] <= 100, f"Invalid ram_pct: {data['ram_pct']}")
        self.assertTrue(0 <= data["disk_pct"] <= 100, f"Invalid disk_pct: {data['disk_pct']}")
        self.assertTrue(len(data["uptime"]) > 0, "Uptime string should not be empty")


class DynamicIslandDashboardArchitectureTest(unittest.TestCase):
    def test_escape_shortcut_handles_focused_drawer_inputs(self):
        content = DASHBOARD_QML.read_text()
        connectivity = CONNECTIVITY_CENTER_QML.read_text()
        # Focused TextInput items may consume Escape before Keys reaches Dashboard.
        self.assertRegex(
            content,
            r'Shortcut\s*\{\s*sequence:\s*"Escape"\s*'
            r'enabled:\s*dashboardWindow\.expanded\s*'
            r'context:\s*Qt\.WindowShortcut\s*'
            r'onActivated:\s*dashboardWindow\.handleEscape\(\)'
        )
        self.assertLess(content.index("Shortcut {"), content.index("id: morphContainer"))
        self.assertIn("if (sideDrawerOpen) {", content)
        self.assertIn("connectivityLoader.item.handleEscape()", content)
        self.assertIn("function handleEscape(): bool", connectivity)
        self.assertIn("else dismiss();", content)

    def test_dashboard_qml_anchoring_and_shape(self):
        content = DASHBOARD_QML.read_text()
        
        # Dashboard renders inside the one existing Island surface.
        island = ISLAND_QML.read_text()
        self.assertIn("top: true", island)
        self.assertIn("IslandShape", island)
        self.assertNotIn("PanelWindow", content)
        self.assertIn("shape: islandShape", island)
        # Dashboard geometry is capped at 900x520 and clamped to the live screen.
        state = ISLAND_STATE_JS.read_text()
        self.assertRegex(state, r"var Dashboard = \{\s*width: 900,\s*height: 520")
        self.assertIn("Math.min(Dashboard.width", state)
        self.assertIn("Math.min(Dashboard.height", state)
        self.assertIn("targetScreen.width, targetScreen.height, 7", island)
        self.assertIn("cardDimensions: islandWindow.dashboardDimensions", island)
        # LayerShell mask verification
        self.assertIn("mask: Region", island)
        # Outside click and Escape key dismissal
        self.assertIn("Keys.onEscapePressed", island)
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
        slider = QUICKSETTING_SLIDER_QML.read_text()
        tile = QUICKSETTING_TILE_QML.read_text()
        # Reusable sliders own the interaction; QuickSettings routes values to services.
        self.assertEqual(content.count("QuickSettingSlider {"), 2)
        self.assertIn('label: qsTr("Volume")', content)
        self.assertIn("Audio.setVolume(value)", content)
        self.assertIn("signal valueRequested(real value)", slider)
        self.assertIn("Accessible.role: Accessible.Slider", slider)
        self.assertIn('label: qsTr("Brightness")', content)
        self.assertIn("DesktopControls.setBrightness(value)", content)
        self.assertIn("brightnessctl", DESKTOP_CONTROLS_QML.read_text())
        # Reusable tiles own activation and details gestures; services own the actions.
        self.assertEqual(content.count("QuickSettingTile {"), 7)
        self.assertIn("Qt.LeftButton | Qt.RightButton", tile)
        self.assertIn('label: qsTr("Wi-Fi")', content)
        self.assertIn('label: qsTr("Bluetooth")', content)
        self.assertIn('label: qsTr("Hotspot")', content)
        self.assertIn("&& !Hotspot.active", content)
        self.assertIn('if (Hotspot.active) return qsTr("Used by Hotspot");', content)
        self.assertIn("Networking.wifiEnabled = expectedWifiState", content)
        self.assertIn("btAdapter.enabled = expectedBluetoothState", content)
        self.assertIn("Hotspot.toggle()", content)
        self.assertIn('onDetailsRequested: root.requestSideDrawer("hotspot")', content)
        self.assertIn("Mute", content)
        self.assertIn("Do Not Disturb", content)

    def test_quick_setting_slider_native_pointer_keyboard_and_amplification(self):
        from test_qml_input import environment

        if not shutil.which("c++") or not shutil.which("pkg-config"):
            self.skipTest("Qt development tools unavailable")
        flags = subprocess.run(
            ["pkg-config", "--cflags", "--libs", "Qt6Quick", "Qt6Qml", "Qt6Test"],
            capture_output=True, text=True,
        )
        if flags.returncode:
            self.skipTest("Qt6 Quick/Qml/Test development packages unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-slider-input-") as directory:
            isolated = Path(directory)
            dashboard = isolated / "dashboard"
            dashboard.mkdir()
            shutil.copyfile(QUICKSETTING_SLIDER_QML, dashboard / "QuickSettingSlider.qml")
            theme = isolated / "theme"
            theme.mkdir()
            (theme / "qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (theme / "Tokens.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property color surface: "#24282c"
    property color surface_high: "#30343a"
    property color outline: "#686d73"
    property color accent: "#77caff"
    property color text_primary: "#ffffff"
    property color text_secondary: "#bbbbbb"
    property color focus_ring: "#77caff"
}
''')
            (isolated / "main.qml").write_text('''import QtQuick
import "./dashboard"
Window {
    width: 280; height: 100; visible: true
    QuickSettingSlider {
        objectName: "control"
        x: 10; y: 10; width: 240; height: implicitHeight
        label: "Volume"; valueText: Math.round(value * 100) + "%"
        value: 0.5; maximum: 1.5
        onValueRequested: requested => value = requested
    }
}
''')
            (isolated / "main.cpp").write_text(r'''
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <cmath>
#include <cstdio>
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv); QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile(argv[1]));
    if (engine.rootObjects().isEmpty()) return 2;
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    auto control = window->findChild<QQuickItem *>("control");
    int failures = 0;
    auto check = [&](bool ok, const char *message) { if (!ok) { fprintf(stderr, "%s\n", message); ++failures; } };
    auto value = [&]() { return control->property("value").toDouble(); };
    QTest::qWait(150); window->requestActivate();
    check(control->height() == 64, "slider module must reserve 64px");
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, QPoint(100, 20));
    check(std::abs(value() - 0.5) < 0.001, "header click changed the value");
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, QPoint(30, 56));
    QTest::mouseMove(window, QPoint(240, 56), 20);
    check(std::abs(value() - 1.5) < 0.001, "pill drag failed to reach amplified maximum");
    check(control->property("displayedValue").toDouble() == 1, "drag feedback lagged behind the pointer");
    QTest::mouseMove(window, QPoint(20, 56), 20);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, QPoint(20, 56));
    check(std::abs(value()) < 0.001, "pill drag failed to reach zero");
    control->forceActiveFocus();
    QTest::keyClick(window, Qt::Key_End);
    check(std::abs(value() - 1.5) < 0.001, "End lost amplified maximum");
    QTest::keyClick(window, Qt::Key_Left);
    check(std::abs(value() - 1.45) < 0.001, "Left ignored step");
    QTest::keyClick(window, Qt::Key_Home);
    QTest::keyClick(window, Qt::Key_Up);
    check(std::abs(value() - 0.05) < 0.001, "Home or Up ignored step");
    control->setProperty("value", 2.1);
    check(value() == 2.1 && control->property("normalizedValue").toDouble() == 1,
          "display clamp discarded the reported amplified value");
    QTest::qWait(60);
    const auto intermediate = control->property("displayedValue").toDouble();
    check(intermediate > 0.05 && intermediate < 1, "external value update did not ease between positions");
    QTest::qWait(180);
    check(control->property("displayedValue").toDouble() == 1, "external value update did not settle");
    control->setProperty("value", 0.7); control->setProperty("available", false);
    QTest::keyClick(window, Qt::Key_End);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, QPoint(240, 56));
    check(value() == 0.7, "unavailable slider accepted input");
    return failures ? 1 : 0;
}
''')
            built = subprocess.run(
                ["c++", "-fPIC", str(isolated / "main.cpp"), "-o", str(isolated / "check")]
                + flags.stdout.split(), capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(built.returncode, 0, built.stderr)
            result = subprocess.run(
                [str(isolated / "check"), str(isolated / "main.qml")],
                capture_output=True, text=True, timeout=8, env=environment(isolated),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotRegex(result.stderr, r"ReferenceError|TypeError|Unable to assign|is not a type")

    def test_quick_settings_brightness_drag_keeps_last_value(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-brightness-drag-") as directory:
            isolated = Path(directory)
            dashboard = isolated / "dashboard"
            dashboard.mkdir()
            shutil.copyfile(QUICKSETTINGS_QML, dashboard / "QuickSettings.qml")
            shutil.copyfile(QUICKSETTING_TILE_QML, dashboard / "QuickSettingTile.qml")
            shutil.copyfile(QUICKSETTING_SLIDER_QML, dashboard / "QuickSettingSlider.qml")
            settings_path = dashboard / "QuickSettings.qml"
            settings_content = settings_path.read_text()
            settings_content = settings_content.replace("import Quickshell.Bluetooth\n", "")
            settings_content = settings_content.replace("import Quickshell.Networking\n", "")
            settings_content = settings_content.replace("DeviceType.Wifi", "0")
            settings_content = settings_content.replace("Networking.", "testNetworking.")
            settings_content = settings_content.replace("Bluetooth.defaultAdapter", "testBluetooth.defaultAdapter")
            settings_content = settings_content.replace("    id: root\n", '''    id: root

    QtObject { id: testNetworking; property var devices: testNetworkDevices; property bool wifiEnabled: true; property bool wifiHardwareEnabled: true }
    QtObject { id: testNetworkDevices; property var values: [testWifiDevice] }
    QtObject { id: testWifiDevice; property int type: 0; property string name: "wlan-primary"; property var networks: testNetworks }
    QtObject { id: testNetworks; property var values: [] }
    QtObject { id: testBluetooth; property var defaultAdapter: testAdapter }
    QtObject { id: testAdapter; property bool enabled: true; property var devices: testBluetoothDevices }
    QtObject { id: testBluetoothDevices; property var values: [] }
    property var testNetworkingRef: testNetworking
''', 1)
            settings_path.write_text(settings_content)
            colors = {
                "surface_high": "#30343a", "surface": "#24282c",
                "outline": "#686d73", "accent": "#77caff",
                "text_primary": "#ffffff", "text_secondary": "#bbbbbb",
                "danger": "#ff8888", "focus_ring": "#77caff",
            }
            theme = isolated / "theme"
            theme.mkdir()
            (theme / "qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (theme / "Tokens.qml").write_text(
                "pragma Singleton\nimport QtQuick\nQtObject {\n"
                + "\n".join(f'    property color {key}: "{value}"' for key, value in colors.items())
                + "\n}\n"
            )
            services = isolated / "services"
            services.mkdir()
            (services / "qmldir").write_text(
                "singleton Audio 1.0 Audio.qml\n"
                "singleton DesktopControls 1.0 DesktopControls.qml\n"
                "singleton Hotspot 1.0 Hotspot.qml\n"
            )
            (services / "Audio.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property real volume: 0.5
    property bool muted: false
    property bool available: true
    function setVolume(value) { volume = value; }
    function toggleMute() { muted = !muted; }
}
''')
            (services / "Hotspot.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool active: false
    property bool canStart: false
    property bool busy: false
    property string deviceName: "wlan-secondary"
    property string tileStatus: "Active on wlan-secondary"
    function toggle() {}
}
''')
            hotspot_path = services / "Hotspot.qml"
            hotspot_path.write_text(hotspot_path.read_text().replace("property bool active: false", "property bool active: true"))
            shutil.copyfile(DESKTOP_CONTROLS_QML, services / "DesktopControls.qml")
            (isolated / "shell.qml").write_text('''import QtQuick
import Quickshell
import "./dashboard"
import "./services"
ShellRoot {
    FloatingWindow {
        width: 280; height: 380; visible: true
        Loader {
            id: settingsLoader
            active: true
            sourceComponent: QuickSettings { anchors.centerIn: parent }
        }
    }
    Timer { interval: 120; running: true; repeat: false; onTriggered: {
        var settings = settingsLoader.item;
        if (settings.wifiDevice.name === Hotspot.deviceName)
            console.error("HOTSPOT_ADAPTER_FIXTURE_FAIL: hotspot matched primary Wi-Fi adapter");
        if (settings.wifiCanToggle) console.error("HOTSPOT_WIFI_TOGGLE_FAIL: global Wi-Fi toggle remained enabled");
        if (settings.wifiSublabel !== "Used by Hotspot") console.error("HOTSPOT_WIFI_LABEL_FAIL: missing active hotspot status");
        settings.toggleWifi();
        if (settings.testNetworkingRef.wifiEnabled !== true || settings.wifiPending)
            console.error("HOTSPOT_WIFI_ACTION_FAIL: blocked toggle changed Wi-Fi state");
        else console.log("HOTSPOT_NONPRIMARY_PASS");
    } }
    Timer {
        interval: 180; running: true; repeat: false
        onTriggered: {
            settingsLoader.item.setBrightness(0.15);
            settingsLoader.item.setBrightness(0.45);
            settingsLoader.item.setBrightness(0.90);
        }
    }
    Timer {
        interval: 340; running: true; repeat: false
        onTriggered: {
            settingsLoader.item.setBrightness(0.25);
            settingsLoader.item.setBrightness(0.66);
        }
    }
    Timer { interval: 380; running: true; repeat: false; onTriggered: settingsLoader.active = false }
    Timer { interval: 1600; running: true; repeat: false; onTriggered: Qt.quit() }
}
''')
            bin_dir = isolated / "bin"
            bin_dir.mkdir()
            fake_brightnessctl = bin_dir / "brightnessctl"
            fake_brightnessctl.write_text('''#!/bin/sh
if [ "$1" = "-m" ]; then
    printf 'mock,backlight,100,60%%\\n'
elif [ "$1" = "set" ]; then
    printf '%s\\n' "$2" >> "$RICE_BRIGHTNESS_LOG"
    sleep 0.3
fi
''')
            fake_brightnessctl.chmod(0o755)
            log = isolated / "brightness.log"
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software",
                       PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                       RICE_BRIGHTNESS_LOG=str(log))
            result = subprocess.run(
                ["quickshell", "--path", str(isolated / "shell.qml"), "--no-color"],
                capture_output=True, text=True, timeout=7, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1000:])
            self.assertNotRegex(
                output, r"ReferenceError|TypeError|Component is not ready|is not a type", output[-1500:]
            )
            self.assertNotIn("HOTSPOT_ADAPTER_FIXTURE_FAIL", output, output[-1000:])
            self.assertNotIn("HOTSPOT_WIFI_TOGGLE_FAIL", output, output[-1000:])
            self.assertNotIn("HOTSPOT_WIFI_LABEL_FAIL", output, output[-1000:])
            self.assertNotIn("HOTSPOT_WIFI_ACTION_FAIL", output, output[-1000:])
            self.assertIn("HOTSPOT_NONPRIMARY_PASS", output, output[-1000:])
            self.assertEqual(log.read_text().splitlines() if log.exists() else [],
                             ["90%", "66%"], output[-1000:])

    def test_system_telemetry_view(self):
        content = SYSTEM_QML.read_text()
        # CPU, RAM, Disk, Uptime indicators
        self.assertIn("cpuPct", content)
        self.assertIn("ramPct", content)
        self.assertIn("diskPct", content)
        self.assertIn("uptime", content)
        self.assertIn("telemetry.py", content)
        self.assertIn("--watch", content)
        self.assertIn("stdout: SplitParser", content)
        self.assertIn("onVisibleChanged", content)
        self.assertIn("processRestart", content)
        self.assertIn('"Last 2.5m"', content)

    def test_config_view(self):
        content = CONFIG_QML.read_text()
        # Theme switcher
        self.assertIn("Dark Mode", content)
        self.assertIn("Light Mode", content)
        queue = THEME_COMMAND_QUEUE_QML.read_text()
        self.assertIn("--theme-mode-changed", queue)
        self.assertIn("reloadPending", queue)
        self.assertIn("pendingCommands", queue)
        # Reload shell buttons
        self.assertIn("Reload Rice Shell", content)
        self.assertIn("Reload Hyprland", content)

    def test_notification_history_records_updates_restores_and_clears(self):
        center = NOTIFICATION_CENTER_QML.read_text()
        self.assertIn("DesktopControls.notificationHistory", center)
        self.assertIn("DesktopControls.clearNotificationHistory()", center)
        self.assertIn("root.expandedNotificationId = null", center)
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")

        with tempfile.TemporaryDirectory(prefix="rice-notification-history-") as directory:
            isolated = Path(directory)
            services = isolated / "services"
            services.mkdir()
            (services / "qmldir").write_text("singleton DesktopControls 1.0 DesktopControls.qml\n")
            shutil.copyfile(DESKTOP_CONTROLS_QML, services / "DesktopControls.qml")
            shell_path = isolated / "shell.qml"
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./services"
ShellRoot {
    Timer { interval: 50; running: true; repeat: false; onTriggered: {
        DesktopControls.recordNotification(1, "First", "Body", "App", "", false);
        DesktopControls.recordNotification(2, "Second", "Body", "App", "", false);
        var history = DesktopControls.notificationHistory;
        if (history.length !== 2 || history[0].id !== 2 || history[1].id !== 1)
            console.error("NOTIFICATION_HISTORY_FAIL: insertion order");

        DesktopControls.recordNotification(1, "Updated", "New body", "App", "", false);
        history = DesktopControls.notificationHistory;
        if (history.length !== 2 || history[0].id !== 1 || history[0].summary !== "Updated")
            console.error("NOTIFICATION_HISTORY_FAIL: update did not move to front");
        DesktopControls.recordNotification(1, "Stale", "", "App", "", true);
        if (DesktopControls.notificationHistory[0].summary !== "Updated")
            console.error("NOTIFICATION_HISTORY_FAIL: stale generation replaced entry");

        var restored = [];
        for (var i = 0; i < 55; i++)
            restored.push({ id: i, summary: "Entry " + i, body: "", appName: "", appIcon: "", time: "" });
        DesktopControls.restoreNotificationHistory(restored);
        history = DesktopControls.notificationHistory;
        if (history.length !== 50 || history[0].id !== 0 || history[49].id !== 49)
            console.error("NOTIFICATION_HISTORY_FAIL: restore limit");
        DesktopControls.clearNotificationHistory();
        if (DesktopControls.notificationHistory.length !== 0)
            console.error("NOTIFICATION_HISTORY_FAIL: clear did not empty history");
        else console.log("NOTIFICATION_HISTORY_PASS");
        Qt.quit();
    } }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")
            result = subprocess.run(
                ["quickshell", "--path", str(shell_path), "--no-color"],
                capture_output=True, text=True, timeout=8, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1200:])
            self.assertNotIn("NOTIFICATION_HISTORY_FAIL", output, output[-1200:])
            self.assertIn("NOTIFICATION_HISTORY_PASS", output, output[-1200:])

    def test_inner_clicks_do_not_dismiss(self):
        content = ISLAND_QML.read_text()
        # One scrim owns both Island and Dashboard bounds.
        self.assertIn("minX = islandContainer.x", content)
        self.assertIn("maxX = islandContainer.x + islandContainer.width", content)
        self.assertIn("!dashboard.containsDrawer", content)
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

        # Side bar pills and a single persistent center surface
        self.assertIn("id: leftIsland", content)
        self.assertNotIn("id: centerIsland", content)
        island = ISLAND_QML.read_text()
        self.assertIn("id: islandContainer", island)
        self.assertIn("id: rightIsland", content)

        # Left Island: launcher icon button and workspaces
        self.assertIn("launcherHover", content)
        self.assertIn("barRoot.requestLauncher()", content)
        self.assertIn("Workspaces", content)

        # Center Island: horizontal center anchoring, dynamic island inline (idle & media), dashboard request
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", island)
        self.assertIn("Control Center", island)
        self.assertIn('islandWindow.requestDashboard("Home")', island)
        self.assertIn("readonly property bool hasMedia: Media.hasPlayer", island)

        # Right Island: status tray and clock pill
        self.assertIn("StatusTray", content)
        self.assertIn("id: clockPill", content)
        self.assertIn("hh:mm", content)

    def test_dynamic_island_media_capsule(self):
        self.assertTrue(ISLAND_QML.exists(), "Island.qml must exist")
        content = ISLAND_QML.read_text()

        # Horizontal expanded media capsule; no synthetic audio visualization.
        self.assertIn("expandedMediaContent", content)
        self.assertTrue("visualizerPhase" not in content, "remove the synthetic phase timer")
        self.assertTrue("visualizerLevel" not in content, "remove the synthetic bar animation")
        self.assertIn("progressBarTrack", content)
        self.assertIn("Media.setPosition", content)
        self.assertIn("Media.previous", content)
        self.assertIn("Media.togglePlaying", content)
        self.assertIn("Media.next", content)
        self.assertIn("seekByOffset(-10)", content)
        self.assertIn("seekByOffset(10)", content)
        self.assertIn('objectName: "mediaPreviousActionLabel"', content)
        self.assertIn('objectName: "mediaNextActionLabel"', content)
        self.assertIn("Media.activePlayer.canSeek && Media.length > 0", content)
        self.assertIn("textFormat: Text.PlainText", content)

        player_card = (ROOT / "config/quickshell/rice-shell/dashboard/PlayerCard.qml").read_text()
        self.assertIn("sourceSize.width: Math.min(840", player_card)
        self.assertIn("Media.activePlayer.canSeek && Media.length > 0", player_card)
        self.assertIn("Media.canToggle", player_card)
        self.assertIn("textFormat: Text.PlainText", player_card)

        # Scrim outside-click and escape dismissal
        self.assertIn("id: scrim", content)
        self.assertIn("Keys.onEscapePressed", content)

        # Media capsule and compact pill are owned by the same window.
        self.assertIn("id: contentViewport", content)
        self.assertIn("id: hoverDwell", content)
        self.assertIn("function islandToggle()", SHELL_QML.read_text())

    def test_player_card_loads_and_disables_seek_without_duration_or_capability(self):
        if not shutil.which("qml6"):
            self.skipTest("qml6 binary unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-player-card-") as directory:
            isolated = Path(directory)
            for folder in ("dashboard", "theme", "services"):
                (isolated / folder).mkdir()
            source = (ROOT / "config/quickshell/rice-shell/dashboard/PlayerCard.qml").read_text()
            source = source.replace(
                "id: root\n", "id: root\n    readonly property alias probeSeekEnabled: playerSeekArea.enabled\n", 1)
            (isolated / "dashboard/PlayerCard.qml").write_text(source)
            (isolated / "theme/qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (isolated / "theme/Tokens.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property color accent: "#78baff"
    property color danger: "#ff6677"
    property color outline: "#667080"
    property color surface: "#20242b"
    property color surface_high: "#303641"
    property color text_primary: "#ffffff"
    property color text_secondary: "#b9c1ce"
}
''')
            (isolated / "services/qmldir").write_text("singleton Media 1.0 Media.qml\n")
            (isolated / "services/Media.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool hasPlayer: true
    property bool isPlaying: false
    property bool canToggle: true
    property bool canPrev: true
    property bool canNext: true
    property string trackTitle: "<b>Example track</b>"
    property string trackArtist: "Example artist"
    property string trackAlbum: "Example album"
    property string trackArtUrl: ""
    property real position: 10
    property real length: 60
    property real progress: position / length
    property QtObject activePlayer: QtObject {
        property bool canSeek: true
        property bool positionSupported: true
    }
    function formatTime(value) { return "0:10"; }
    function setPosition(value) {}
    function previous() {}
    function togglePlaying() {}
    function next() {}
}
''')
            (isolated / "Main.qml").write_text('''import QtQuick
import QtQuick.Window
import "./dashboard"
import "./services"
Window {
    visible: true
    width: 280; height: 220
    PlayerCard { id: card; anchors.fill: parent }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: {
            if (!card.probeSeekEnabled) console.error("PLAYER_SEEK_FAIL: capable player was disabled");
            if (card.artworkScale < 1 || card.artworkScale > 3)
                console.error("PLAYER_ARTWORK_FAIL: source scale was not bounded");
            Media.activePlayer.canSeek = false;
            if (card.probeSeekEnabled) console.error("PLAYER_SEEK_FAIL: non-seekable player remained enabled");
            Media.activePlayer.canSeek = true;
            Media.length = 0;
            if (card.probeSeekEnabled) console.error("PLAYER_SEEK_FAIL: unknown duration remained enabled");
            Qt.quit();
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            result = subprocess.run(
                ["qml6", "-f", str(isolated / "Main.qml"), "--quit-after", "1500"],
                capture_output=True, text=True, env=env, timeout=5,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("PLAYER_SEEK_FAIL", output, output[-1400:])
            self.assertNotIn("PLAYER_ARTWORK_FAIL", output, output[-1400:])

    def test_media_service_rejects_invalid_position_and_unknown_duration_seeks(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-media-service-") as directory:
            isolated = Path(directory)
            (isolated / "services").mkdir()
            source = MEDIA_QML.read_text()
            source = source.replace("import Quickshell\n", "")
            source = source.replace("import Quickshell.Services.Mpris\n", "import \".\"\n")
            source = source.replace("MprisPlayer activePlayer", "QtObject activePlayer")
            (isolated / "services/Media.qml").write_text(source)
            (isolated / "services/qmldir").write_text(
                "singleton Media 1.0 Media.qml\nsingleton Mpris 1.0 Mpris.qml\n")
            (isolated / "services/Mpris.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property QtObject player: QtObject {
        property bool isPlaying: false
        property bool canTogglePlaying: true
        property bool canPlay: true
        property bool canPause: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        property bool canSeek: true
        property bool positionSupported: true
        property string trackTitle: "Track"
        property string trackArtist: "Artist"
        property string trackAlbum: "Album"
        property string trackArtUrl: ""
        property real position: 10
        property real length: 60
        function togglePlaying() {}
        function pause() {}
        function play() {}
        function next() {}
        function previous() {}
    }
    property var players: ({ values: [player] })
}
''')
            (isolated / "Main.qml").write_text('''import QtQuick
import Quickshell
import "./services"
ShellRoot {
    FloatingWindow {
        visible: true
        width: 100; height: 100
        Timer {
            interval: 80; running: true; repeat: false
            onTriggered: {
                if (Media.length !== 60 || Math.abs(Media.progress - 1 / 6) > 0.001)
                    console.error("MEDIA_PROGRESS_FAIL: initial position was not normalized");
                Media.setPosition(30);
                if (Mpris.player.position !== 30)
                    console.error("MEDIA_SEEK_FAIL: supported seek was not dispatched");
                Mpris.player.position = 12;
                Mpris.player.length = 0;
                Media.setPosition(40);
                if (Mpris.player.position !== 12)
                    console.error("MEDIA_SEEK_FAIL: unknown duration changed position");
                Mpris.player.length = 60;
                Mpris.player.canSeek = false;
                Media.setPosition(40);
                if (Mpris.player.position !== 12)
                    console.error("MEDIA_SEEK_FAIL: non-seekable player changed position");
                Mpris.player.canSeek = true;
                Mpris.player.position = Infinity;
                if (Media.position !== 0 || Media.progress !== 0
                    || Media.formatTime(Infinity) !== "0:00")
                    console.error("MEDIA_PROGRESS_FAIL: nonfinite values escaped normalization");
                Qt.quit();
            }
        }
    }
}
''')
            runtime = isolated / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       NO_AT_BRIDGE="1", XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(isolated / "config"),
                       XDG_CACHE_HOME=str(isolated / "cache"))
            for name in ("WAYLAND_DISPLAY", "QT_WAYLAND_DISPLAY", "DISPLAY"):
                env.pop(name, None)
            result = subprocess.run(
                ["quickshell", "--path", str(isolated / "Main.qml"), "--no-color"],
                capture_output=True, text=True, env=env, timeout=5,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("MEDIA_PROGRESS_FAIL", output, output[-1400:])
            self.assertNotIn("MEDIA_SEEK_FAIL", output, output[-1400:])

    def test_native_bluetooth_drawer_instantiates_and_tracks_device_state(self):
        shell_dir = BT_DRAWER_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-bluetooth-native-test-") as directory:
            isolated = Path(directory)
            for relative in ("dashboard/BluetoothDrawer.qml", "theme/Tokens.qml", "theme/qmldir"):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)

            shell_path = isolated / "shell.qml"
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 440; height: 500; visible: true
        BluetoothDrawer {
            id: drawer
            visible: false // Avoid touching the host Bluetooth adapter.
            Component.onCompleted: console.log("BT_NATIVE_LOADED", drawer.devices.length)
        }
    }
    Timer { interval: 250; running: true; repeat: false; onTriggered: Qt.quit() }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")

            def run_shell():
                try:
                    result = subprocess.run(
                        ["quickshell", "--path", str(shell_path), "--no-color"],
                        capture_output=True, text=True, timeout=6, env=env,
                    )
                except FileNotFoundError:
                    self.skipTest("quickshell binary unavailable")
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output[-1200:])
                self.assertNotIn("QQmlComponent: Component is not ready", output, output[-1200:])
                return output

            self.assertIn("BT_NATIVE_LOADED", run_shell())

            drawer_path = isolated / "dashboard/BluetoothDrawer.qml"
            content = drawer_path.read_text()
            original = "    property var adapterOverride: null"
            self.assertEqual(content.count(original), 1)
            fake = '''
    QtObject { id: testDevice; property string address: "01:02:03:04:05:06"; property string name: "Test headset"; property bool connected: false; property bool paired: true }
    QtObject { id: testDeviceTwo; property string address: "01:02:03:04:05:07"; property string name: "Test headset"; property bool connected: false; property bool paired: false }
    QtObject { id: testModel; property var values: [testDevice] }
    QtObject { id: testAdapter; property bool enabled: true; property bool discovering: false; property var devices: testModel }
    property var testDeviceRef: testDevice
    property var testDeviceTwoRef: testDeviceTwo
    property var testModelRef: testModel
    property var testAdapterRef: testAdapter
    property var adapterOverride: testAdapter'''
            drawer_path.write_text(content.replace(original, fake))
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 440; height: 500; visible: true
        BluetoothDrawer { id: drawer; visible: false }
        Timer { interval: 80; running: true; repeat: false; onTriggered: {
            drawer.testDeviceRef.connected = true;
            drawer.testAdapterRef.discovering = true;
            drawer.visible = true;
            drawer.visible = false;
            if (!drawer.testAdapterRef.discovering) console.error("BT_FOREIGN_SCAN_FAIL");
            drawer.testAdapterRef.discovering = false;
            drawer.visible = true;
            if (!drawer.testAdapterRef.discovering) console.error("BT_OWN_SCAN_START_FAIL");
            drawer.isConnecting = true;
            drawer.actionStage = "waiting-agent";
            drawer.handleAgentOutput("Confirm pass");
            drawer.handleAgentOutput("Confirm passkey 123456");
            if (drawer.pairingPromptType !== "confirm") console.error("BT_SPLIT_PROMPT_FAIL");
            drawer.pairingPromptType = "";
            drawer.handleAgentOutput("Confirm passkey 123456\\nWaiting for device response");
            if (drawer.pairingPromptType !== "") console.error("BT_STALE_PROMPT_FAIL");
            drawer.visible = false;
            drawer.handleAgentOutput("Confirm passkey 123456 Confirm passkey 654321");
            if (drawer.testAdapterRef.discovering || drawer.isConnecting || drawer.pairingPromptType !== "")
                console.error("BT_CLOSE_CLEANUP_FAIL");
            else console.log("BT_LIFECYCLE_PASS");
        } }
        Timer { interval: 180; running: true; repeat: false; onTriggered: {
            if (drawer.devices.length === 1 && drawer.devices[0].connected)
                console.log("BT_REACTIVE_PASS");
            else console.error("BT_REACTIVE_FAIL");
            drawer.testModelRef.values = [drawer.testDeviceRef, drawer.testDeviceTwoRef];
            if (drawer.devices.length !== 2) console.error("BT_ADD_FAIL");
            drawer.testDeviceTwoRef.paired = true;
            if (drawer.devices.length !== 2 || !drawer.devices[1].paired)
                console.error("BT_PAIRED_FAIL");
            drawer.testModelRef.values = [drawer.testDeviceTwoRef];
            if (drawer.devices.length !== 1 || drawer.devices[0].mac !== drawer.testDeviceTwoRef.address)
                console.error("BT_REMOVE_FAIL");
            else console.log("BT_INVENTORY_PASS");
            Qt.quit();
        } }
    }
}
''')
            output = run_shell()
            self.assertIn("BT_REACTIVE_PASS", output, output[-1200:])
            self.assertIn("BT_LIFECYCLE_PASS", output, output[-1200:])
            self.assertIn("BT_INVENTORY_PASS", output, output[-1200:])
            self.assertNotIn("BT_REACTIVE_FAIL", output, output[-1200:])
            self.assertNotIn("_FAIL", output, output[-1200:])

    def test_connectivity_center_routes_network_pages(self):
        self.assertTrue(WIFI_DRAWER_QML.exists(), "WifiDrawer.qml must exist")
        self.assertTrue(BT_DRAWER_QML.exists(), "BluetoothDrawer.qml must exist")
        self.assertTrue(CONNECTIVITY_CENTER_QML.exists(), "ConnectivityCenter.qml must exist")

        wifi_content = WIFI_DRAWER_QML.read_text()
        bt_content = BT_DRAWER_QML.read_text()
        center_content = CONNECTIVITY_CENTER_QML.read_text()
        qs_content = QUICKSETTINGS_QML.read_text()
        tile_content = QUICKSETTING_TILE_QML.read_text()

        # Wi-Fi drawer: native networking, scanning, password and connection actions
        self.assertIn("import Quickshell.Networking", wifi_content)
        self.assertIn("Networking.devices.values", wifi_content)
        self.assertIn("DeviceType.Wifi", wifi_content)
        self.assertIn('property: "scannerEnabled"', wifi_content)
        self.assertIn("function connectNetwork(network, withPassword)", wifi_content)
        self.assertIn("network.connectWithPsk(secret)", wifi_content)
        self.assertIn("network.connect()", wifi_content)
        self.assertIn("network.disconnect()", wifi_content)
        self.assertIn("passwordField", wifi_content)
        self.assertIn("closeRequested", wifi_content)

        # Bluetooth drawer: reactive native inventory/scanning; CLI retained for pairing prompts.
        self.assertIn("import Quickshell.Bluetooth", bt_content)
        self.assertIn("Bluetooth.defaultAdapter", bt_content)
        self.assertIn("btAdapter.devices.values", bt_content)
        self.assertIn("btAdapter.discovering = true", bt_content)
        self.assertNotIn('"bluetoothctl", "devices"', bt_content)
        self.assertNotIn("devicePollingTimer", bt_content)
        self.assertIn("bluetoothctl", bt_content)
        self.assertIn("devices", bt_content)
        self.assertIn("scan", bt_content)
        self.assertIn("closeRequested", bt_content)

        # QuickSettings owns service toggles and requests pages through reusable tiles.
        self.assertNotIn("wifiDrawerOpen", qs_content)
        self.assertNotIn("btDrawerOpen", qs_content)
        self.assertNotIn("WifiDrawer {", qs_content)
        self.assertNotIn("BluetoothDrawer {", qs_content)
        self.assertIn("Qt.RightButton", tile_content)
        self.assertIn("requestSideDrawer", qs_content)
        self.assertIn('onDetailsRequested: root.requestSideDrawer("wifi")', qs_content)
        self.assertIn('onDetailsRequested: root.requestSideDrawer("bluetooth")', qs_content)
        self.assertIn('onDetailsRequested: root.requestSideDrawer("hotspot")', qs_content)

        # ConnectivityCenter owns the Wi-Fi, Bluetooth, and Hotspot pages.
        self.assertIn('Accessible.name: "Connectivity Center"', center_content)
        self.assertIn('{ id: "wifi", label: "Wi-Fi"', center_content)
        self.assertIn('{ id: "bluetooth", label: "Bluetooth"', center_content)
        self.assertIn('{ id: "hotspot", label: "Hotspot"', center_content)
        self.assertIn('source: "WifiDrawer.qml"', center_content)
        self.assertIn('source: "BluetoothDrawer.qml"', center_content)
        self.assertIn('source: "HotspotDrawer.qml"', center_content)
        self.assertIn("active: root.hotspotVisited", center_content)
        self.assertIn("onHotspotPageRequested", center_content)

        # Dashboard owns one lazy-loaded ConnectivityCenter sidecar.
        dash_content = DASHBOARD_QML.read_text()
        self.assertIn("sideDrawerContainer", dash_content)
        self.assertIn("activeSideDrawer", dash_content)
        self.assertIn("sideDrawerOpen", dash_content)
        self.assertIn("toggleSideDrawer", dash_content)
        self.assertIn("id: homeLoader", dash_content)
        self.assertIn("sourceComponent: Home {", dash_content)
        self.assertIn("id: connectivityLoader", dash_content)
        self.assertIn("sourceComponent: ConnectivityCenter {", dash_content)
        self.assertIn("currentPage: dashboardWindow.renderedSideDrawer", dash_content)
        self.assertNotIn("WifiDrawer", dash_content)
        self.assertNotIn("BluetoothDrawer", dash_content)

    def test_wifi_drawer_scanner_preserves_foreign_scan_ownership_and_clears_passwords(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        shell_dir = WIFI_DRAWER_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-wifi-hardening-test-") as directory:
            isolated = Path(directory)
            for relative in ("dashboard/WifiDrawer.qml", "dashboard/RoundedButton.qml",
                             "dashboard/ActionMenu.qml", "dashboard/ActionMenuItem.qml",
                             "theme/Tokens.qml", "theme/qmldir"):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)
            services = isolated / "services"
            services.mkdir()
            (services / "qmldir").write_text("singleton Hotspot 1.0 Hotspot.qml\n")
            (services / "Hotspot.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool active: false
    property string devicePath: ""
}
''')

            drawer_path = isolated / "dashboard/WifiDrawer.qml"
            content = drawer_path.read_text()
            # Inject fake networking state while retaining the production state handlers.
            replacement = '''
    QtObject {
        id: testNetworking
        property bool canCheckConnectivity: false
        property bool connectivityCheckEnabled: false
        property int connectivity: 0
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
    }
    QtObject {
        id: fakeNet
        property var device: fakeDev
        property string name: "RiceAP"
        property real signalStrength: 0.85
        property bool connected: false
        property bool known: false
        property int security: WifiSecurityType.Wpa2Psk
        property bool stateChanging: false
        property int state: 0
        signal connectionFailed(int reason)
        function connect(): void { stateChanging = true; }
        function connectWithPsk(key): void { stateChanging = true; }
        function disconnect(): void { stateChanging = true; }
    }
    QtObject {
        id: fakeNetModel
        property var values: [fakeNet]
    }
    QtObject {
        id: fakeDev
        property string name: "wlan0"
        property int mode: WifiDeviceMode.Station
        property bool connected: false
        property bool scannerEnabled: false
        property var networks: fakeNetModel
    }
    property var fakeDevRef: fakeDev
    property var fakeNetRef: fakeNet
    property var testWifiDevices: [fakeDev]
    readonly property var wifiDevices: testWifiDevices'''
            idx = content.index("    readonly property var wifiDevices: {")
            end_idx = content.index("    property var selectedWifiDevice:", idx)
            content = content[:idx] + replacement + "\n" + content[end_idx:]
            content = content.replace("Networking.", "testNetworking.")
            drawer_path.write_text(content)

            shell_path = isolated / "shell.qml"
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 440; height: 500; visible: true
        WifiDrawer { id: drawer; visible: false }

        Timer { interval: 60; running: true; repeat: false; onTriggered: {
            // 1. Foreign scan ownership preservation:
            // If another component had already enabled scanner, closing drawer must not disable it.
            drawer.fakeDevRef.scannerEnabled = true;
            drawer.visible = true;
            drawer.visible = false;
            if (!drawer.fakeDevRef.scannerEnabled) console.error("WIFI_FOREIGN_SCAN_FAIL: foreign scan stopped on close");
            else console.log("WIFI_FOREIGN_SCAN_PASS");

            // 2. Own scan ownership:
            // When drawer starts scan, closing drawer restores scannerEnabled = false.
            drawer.fakeDevRef.scannerEnabled = false;
            drawer.visible = true;
            if (!drawer.fakeDevRef.scannerEnabled) console.error("WIFI_OWN_SCAN_START_FAIL");
            drawer.visible = false;
            if (drawer.fakeDevRef.scannerEnabled) console.error("WIFI_OWN_SCAN_STOP_FAIL: own scan not stopped on close");
            else console.log("WIFI_OWN_SCAN_PASS");

            // 3. Password clearing on hide/cancel/success/failed/destroy:
            drawer.visible = true;
            drawer.selectedNetwork = drawer.fakeNetRef;
            drawer.passwordText = "supersecret";
            drawer.showPassword = true;
            drawer.operationPending = true;
            // Hide while operation is in flight - password must be cleared!
            drawer.visible = false;
            if (drawer.passwordText !== "" || drawer.showPassword)
                console.error("WIFI_PASSWORD_HIDE_FAIL: password retained on hide: " + drawer.passwordText);
            else console.log("WIFI_PASSWORD_HIDE_PASS");

            // Cancel password clears password and selection
            drawer.visible = true;
            drawer.selectedNetwork = drawer.fakeNetRef;
            drawer.passwordText = "secret2";
            if (typeof drawer.cancelPassword === "function") drawer.cancelPassword();
            else { drawer.selectedNetwork = null; drawer.passwordText = ""; }
            if (drawer.passwordText !== "" || drawer.selectedNetwork !== null) console.error("WIFI_PASSWORD_CANCEL_FAIL");
            else console.log("WIFI_PASSWORD_CANCEL_PASS");

            // 4. Adapter disappearance while connecting resets pending state
            drawer.operationPending = true;
            drawer.pendingNetwork = drawer.fakeNetRef;
            drawer.testWifiDevices = [];
            if (drawer.operationPending || drawer.pendingNetwork !== null) console.error("WIFI_ADAPTER_DISAPPEAR_FAIL: still connecting after adapter removed");
            else console.log("WIFI_ADAPTER_DISAPPEAR_PASS");

            // 5. StateChanging cancellation / disconnect handling
            drawer.testWifiDevices = [drawer.fakeDevRef];
            drawer.pendingNetwork = drawer.fakeNetRef;
            drawer.pendingAction = "disconnect";
            drawer.operationPending = true;
            drawer.fakeNetRef.stateChanging = true;
            drawer.fakeNetRef.stateChanging = false;
            if (drawer.operationPending) console.error("WIFI_STATE_CHANGING_STUCK_FAIL");
            else console.log("WIFI_STATE_CHANGING_PASS");

            Qt.quit();
        } }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")
            result = subprocess.run(
                ["quickshell", "--path", str(shell_path), "--no-color"],
                capture_output=True, text=True, timeout=8, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1200:])
            self.assertNotIn("WIFI_FOREIGN_SCAN_FAIL", output, output[-1200:])
            self.assertNotIn("WIFI_PASSWORD_HIDE_FAIL", output, output[-1200:])
            self.assertNotIn("WIFI_ADAPTER_DISAPPEAR_FAIL", output, output[-1200:])
            self.assertNotIn("WIFI_STATE_CHANGING_STUCK_FAIL", output, output[-1200:])
            self.assertIn("WIFI_FOREIGN_SCAN_PASS", output, output[-1200:])
            self.assertIn("WIFI_PASSWORD_HIDE_PASS", output, output[-1200:])
            self.assertIn("WIFI_ADAPTER_DISAPPEAR_PASS", output, output[-1200:])
            self.assertIn("WIFI_STATE_CHANGING_PASS", output, output[-1200:])

    def test_bluetooth_drawer_target_mac_correlation_and_validation(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        shell_dir = BT_DRAWER_QML.parents[1]
        with tempfile.TemporaryDirectory(prefix="rice-bluetooth-hardening-test-") as directory:
            isolated = Path(directory)
            for relative in ("dashboard/BluetoothDrawer.qml", "theme/Tokens.qml", "theme/qmldir"):
                destination = isolated / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(shell_dir / relative, destination)

            drawer_path = isolated / "dashboard/BluetoothDrawer.qml"
            content = drawer_path.read_text()
            original = "    property var adapterOverride: null"
            fake = '''
    QtObject { id: testDevA; property string address: "01:02:03:04:05:06"; property string name: "Device A"; property bool connected: false; property bool paired: false }
    QtObject { id: testModel; property var values: [testDevA] }
    QtObject { id: testAdapter; property bool enabled: true; property bool discovering: false; property var devices: testModel }
    property var adapterOverride: testAdapter'''
            self.assertEqual(content.count(original), 1)
            drawer_path.write_text(content.replace(original, fake))

            shell_path = isolated / "shell.qml"
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    FloatingWindow {
        width: 440; height: 500; visible: true
        BluetoothDrawer { id: drawer; visible: true }

        Timer { interval: 60; running: true; repeat: false; onTriggered: {
            // 1. MAC Validation: reject malformed or command-injection MACs
            drawer.connectDevice({ mac: "invalid-mac; echo pwned", name: "Malicious", paired: false, connected: false });
            if (drawer.isConnecting) console.error("BT_INVALID_MAC_FAIL: allowed invalid MAC");
            else console.log("BT_INVALID_MAC_PASS");

            // 2. Target MAC Correlation: output from unrelated device must NOT advance active action
            drawer.connectDevice({ mac: "01:02:03:04:05:06", name: "Device A", paired: true, connected: false });
            drawer.actionStage = "connect";
            // Unrelated device connects
            drawer.handleAgentOutput("[CHG] Device 11:22:33:44:55:66 Connected: yes\\n");
            if (!drawer.isConnecting || drawer.actionStage !== "connect") console.error("BT_UNRELATED_MAC_FAIL: unrelated device marked active device connected");
            else console.log("BT_UNRELATED_MAC_PASS");

            // Unrelated device passkey prompt
            drawer.handleAgentOutput("[agent] Confirm passkey 999999 (Device 11:22:33:44:55:66)\\n");
            if (drawer.pairingPromptType !== "") console.error("BT_UNRELATED_PROMPT_FAIL: unrelated device triggered pairing prompt");
            else console.log("BT_UNRELATED_PROMPT_PASS");

            // Target device connects
            drawer.handleAgentOutput("[CHG] Device 01:02:03:04:05:06 Connected: yes\\n");
            if (drawer.isConnecting) console.error("BT_TARGET_MAC_FAIL: target device did not complete connection");
            else console.log("BT_TARGET_MAC_PASS");

            // 3. Passkey validation: reject non-6-digit passkey
            drawer.pairingPromptType = "passkey";
            drawer.pairingInputText = "123\\nmalicious";
            drawer.answerPairing(true);
            if (drawer.pairingPromptType !== "passkey") console.error("BT_INVALID_PASSKEY_FAIL: accepted invalid passkey");
            else console.log("BT_INVALID_PASSKEY_PASS");

            Qt.quit();
        } }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software")
            result = subprocess.run(
                ["quickshell", "--path", str(shell_path), "--no-color"],
                capture_output=True, text=True, timeout=8, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1200:])
            self.assertNotIn("BT_INVALID_MAC_FAIL", output, output[-1200:])
            self.assertNotIn("BT_UNRELATED_MAC_FAIL", output, output[-1200:])
            self.assertNotIn("BT_UNRELATED_PROMPT_FAIL", output, output[-1200:])
            self.assertNotIn("BT_TARGET_MAC_FAIL", output, output[-1200:])
            self.assertNotIn("BT_INVALID_PASSKEY_FAIL", output, output[-1200:])
            self.assertIn("BT_INVALID_MAC_PASS", output, output[-1200:])
            self.assertIn("BT_UNRELATED_MAC_PASS", output, output[-1200:])
            self.assertIn("BT_UNRELATED_PROMPT_PASS", output, output[-1200:])
            self.assertIn("BT_TARGET_MAC_PASS", output, output[-1200:])
            self.assertIn("BT_INVALID_PASSKEY_PASS", output, output[-1200:])

    def test_desktop_controls_brightness_hardening(self):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell binary unavailable")
        with tempfile.TemporaryDirectory(prefix="rice-desktop-controls-test-") as directory:
            isolated = Path(directory)
            services = isolated / "services"
            services.mkdir()
            (services / "qmldir").write_text("singleton DesktopControls 1.0 DesktopControls.qml\n")
            shutil.copyfile(DESKTOP_CONTROLS_QML, services / "DesktopControls.qml")

            bin_dir = isolated / "bin"
            bin_dir.mkdir()
            fake_brightnessctl = bin_dir / "brightnessctl"
            fake_brightnessctl.write_text('''#!/bin/sh
if [ "$1" = "-m" ]; then
    if [ -f "$RICE_BRIGHTNESS_ABSENT" ]; then
        echo "No backlight device found" >&2
        exit 1
    fi
    printf 'mock,backlight,100,50%%\\n'
elif [ "$1" = "set" ]; then
    if [ -f "$RICE_BRIGHTNESS_FAIL_WRITE" ]; then
        echo "Write failed" >&2
        exit 1
    fi
    printf '%s\\n' "$2" >> "$RICE_BRIGHTNESS_LOG"
fi
''')
            fake_brightnessctl.chmod(0o755)

            shell_path = isolated / "shell.qml"
            shell_path.write_text('''
import QtQuick
import Quickshell
import "./services"
ShellRoot {
    property var lastError: ""
    Connections {
        target: DesktopControls
        function onErrorOccurred(msg) { lastError = msg; }
    }

    Timer { interval: 50; running: true; repeat: false; onTriggered: {
        // 1. Non-finite brightness handling
        DesktopControls.brightnessLevel = 0.5;
        DesktopControls.setBrightness(NaN);
        if (isNaN(DesktopControls.brightnessLevel)) console.error("DESKTOP_NONFINITE_FAIL: NaN brightness accepted");
        else console.log("DESKTOP_NONFINITE_PASS");

        // 2. Reader absent device / no-match clears pending OSD
        DesktopControls.refreshBrightness(true);
        if (!DesktopControls.brightnessOsdPending) console.error("DESKTOP_OSD_PENDING_INIT_FAIL");
    } }

    Timer { interval: 350; running: true; repeat: false; onTriggered: {
        // After reader finishes on absent device, brightnessOsdPending must be cleared!
        if (DesktopControls.brightnessOsdPending) console.error("DESKTOP_ABSENT_OSD_FAIL: brightnessOsdPending stuck true on absent device");
        else console.log("DESKTOP_ABSENT_OSD_PASS");

        // 3. Writer failure handles error and clears pending OSD
        DesktopControls.brightnessOsdPending = true;
        DesktopControls.setBrightness(0.9);
        DesktopControls.flushBrightness();
    } }

    Timer { interval: 650; running: true; repeat: false; onTriggered: {
        if (lastError === "") console.error("DESKTOP_WRITE_FAIL_ERR_MISSING: errorOccurred not emitted on write failure");
        else console.log("DESKTOP_WRITE_FAIL_PASS");
        if (DesktopControls.brightnessOsdPending) console.error("DESKTOP_WRITE_FAIL_OSD_FAIL: brightnessOsdPending stuck true after writer failure");
        else console.log("DESKTOP_WRITE_OSD_PASS");

        Qt.quit();
    } }
}
''')
            env = dict(
                os.environ,
                QT_QPA_PLATFORM="offscreen",
                QSG_RHI_BACKEND="software",
                PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                RICE_BRIGHTNESS_ABSENT=str(isolated / "absent"),
                RICE_BRIGHTNESS_FAIL_WRITE=str(isolated / "fail_write"),
                RICE_BRIGHTNESS_LOG=str(isolated / "brightness.log"),
            )
            (isolated / "absent").touch()
            (isolated / "fail_write").touch()
            result = subprocess.run(
                ["quickshell", "--path", str(shell_path), "--no-color"],
                capture_output=True, text=True, timeout=8, env=env,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-1200:])
            self.assertNotIn("DESKTOP_NONFINITE_FAIL", output, output[-1200:])
            self.assertNotIn("DESKTOP_ABSENT_OSD_FAIL", output, output[-1200:])
            self.assertNotIn("DESKTOP_WRITE_FAIL_ERR_MISSING", output, output[-1200:])
            self.assertNotIn("DESKTOP_WRITE_FAIL_OSD_FAIL", output, output[-1200:])
            self.assertIn("DESKTOP_NONFINITE_PASS", output, output[-1200:])
            self.assertIn("DESKTOP_ABSENT_OSD_PASS", output, output[-1200:])
            self.assertIn("DESKTOP_WRITE_FAIL_PASS", output, output[-1200:])
            self.assertIn("DESKTOP_WRITE_OSD_PASS", output, output[-1200:])


if __name__ == "__main__":
    unittest.main()
