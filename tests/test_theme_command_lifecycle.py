"""Ensure a queued theme command outlives its Dashboard presentation loader."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL_DIR = ROOT / "config/quickshell/rice-shell"


@unittest.skipUnless(shutil.which("quickshell"), "Quickshell required")
class ThemeCommandLifecycleTest(unittest.TestCase):
    def prepare_shell_tree(self, base):
        for name in ("dashboard", "theme", "services"):
            (base / name).mkdir()
        shutil.copyfile(SHELL_DIR / "dashboard/Config.qml", base / "dashboard/Config.qml")
        shutil.copyfile(SHELL_DIR / "theme/Tokens.qml", base / "theme/Tokens.qml")
        shutil.copyfile(SHELL_DIR / "theme/qmldir", base / "theme/qmldir")
        (base / "services/qmldir").write_text(
            "singleton ThemeCommandQueue 1.0 ThemeCommandQueue.qml\n"
        )
        shutil.copyfile(SHELL_DIR / "services/ThemeCommandQueue.qml",
                        base / "services/ThemeCommandQueue.qml")

    def run_until_marker(self, base, main, marker, timeout=5):
        runtime_dir = base / "runtime"
        runtime_dir.mkdir(mode=0o700, exist_ok=True)
        config_home = base / "config"
        config_home.mkdir(exist_ok=True)
        state_home = base / "state"
        (state_home / "desktop-wallpaper").mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(config_home),
                   XDG_STATE_HOME=str(state_home), XDG_RUNTIME_DIR=str(runtime_dir),
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
        for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(name, None)
        process = subprocess.Popen(["quickshell", "--path", str(main), "--no-color"],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1)
        output = ""
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([process.stdout], [], [], 0.1)
                if not ready:
                    if process.poll() is not None:
                        break
                    continue
                line = process.stdout.readline()
                output += line
                if marker in line:
                    break
        finally:
            process.terminate()
            process.wait(timeout=2)
            process.stdout.close()
        return output

    def test_running_command_finishes_after_config_loader_closes(self):
        with tempfile.TemporaryDirectory(prefix="rice-theme-lifecycle-") as directory:
            base = Path(directory)
            for name in ("dashboard", "theme", "services"):
                (base / name).mkdir()
            shutil.copyfile(SHELL_DIR / "dashboard/Config.qml", base / "dashboard/Config.qml")
            shutil.copyfile(SHELL_DIR / "theme/Tokens.qml", base / "theme/Tokens.qml")
            shutil.copyfile(SHELL_DIR / "theme/qmldir", base / "theme/qmldir")
            (base / "services/qmldir").write_text(
                "singleton ThemeCommandQueue 1.0 ThemeCommandQueue.qml\n"
            )
            shutil.copyfile(SHELL_DIR / "services/ThemeCommandQueue.qml",
                            base / "services/ThemeCommandQueue.qml")
            marker = base / "completion.marker"
            slow_command = base / "slow_command.py"
            slow_command.write_text(
                "from pathlib import Path\n"
                "import sys, time\n"
                "time.sleep(0.45)\n"
                "Path(sys.argv[1]).write_text('completed')\n"
            )
            main = base / "main.qml"
            main.write_text('''import QtQuick
import Quickshell
import "./dashboard"
import "./services"
ShellRoot {
    Loader {
        id: configLoader
        active: true
        sourceComponent: Config { }
    }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: {
            if (!configLoader.item) { console.error("THEME_LIFECYCLE_FAIL:no Config item"); return; }
            configLoader.item.queueCommand([__PYTHON__, __SLOW__, __MARKER__]);
            console.log("THEME_LIFECYCLE_STARTED:" + ThemeCommandQueue.running
                + ":" + ThemeCommandQueue.pendingCount + ":" + ThemeCommandQueue.result);
        }
    }
    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: {
            configLoader.active = false;
            console.log("THEME_LIFECYCLE_CLOSED:" + ThemeCommandQueue.running
                + ":" + ThemeCommandQueue.pendingCount + ":" + ThemeCommandQueue.result);
        }
    }
    Timer {
        interval: 700; running: true; repeat: false
        onTriggered: console.log("THEME_LIFECYCLE_LATE:" + ThemeCommandQueue.running
            + ":" + ThemeCommandQueue.pendingCount + ":" + ThemeCommandQueue.result)
    }
    Timer {
        interval: 1000; running: true; repeat: false
        onTriggered: console.log("THEME_LIFECYCLE_CHECK")
    }
}
'''.replace("__PYTHON__", json.dumps(shutil.which("python3")))
            .replace("__SLOW__", json.dumps(str(slow_command)))
            .replace("__MARKER__", json.dumps(str(marker))))
            runtime_dir = base / "runtime"
            runtime_dir.mkdir(mode=0o700)
            config_home = base / "config"
            config_home.mkdir()
            state_home = base / "state"
            (state_home / "desktop-wallpaper").mkdir(parents=True)
            env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(config_home),
                       XDG_STATE_HOME=str(state_home), XDG_RUNTIME_DIR=str(runtime_dir),
                       QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
            for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                env.pop(name, None)
            process = subprocess.Popen(["quickshell", "--path", str(main), "--no-color"],
                                       env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, bufsize=1)
            output = ""
            deadline = time.monotonic() + 4
            try:
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([process.stdout], [], [], 0.1)
                    if not ready:
                        if process.poll() is not None:
                            break
                        continue
                    line = process.stdout.readline()
                    output += line
                    if "THEME_LIFECYCLE_CHECK" in line or "THEME_LIFECYCLE_FAIL" in line:
                        break
            finally:
                process.terminate()
                process.wait(timeout=2)
                process.stdout.close()
            self.assertIn("THEME_LIFECYCLE_CHECK", output, output)
            self.assertTrue(marker.exists(), output)
            self.assertEqual(marker.read_text(), "completed")

    def test_pending_theme_commands_keep_only_the_latest_request(self):
        with tempfile.TemporaryDirectory(prefix="rice-theme-coalesce-") as directory:
            base = Path(directory)
            self.prepare_shell_tree(base)
            marker_dir = base / "markers"
            marker_dir.mkdir()
            theme_script = base / "generate-theme.py"
            theme_script.write_text(
                "from pathlib import Path\n"
                "import sys, time\n"
                "time.sleep(0.3)\n"
                "Path(sys.argv[2], sys.argv[1] + '.done').write_text('done')\n"
            )
            main = base / "main.qml"
            qml = '''import QtQuick
import Quickshell
import "./dashboard"
ShellRoot {
    Loader { id: configLoader; active: true; sourceComponent: Config { } }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: configLoader.item.queueCommand([__PYTHON__, __SCRIPT__, "running", __MARKERS__])
    }
    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: configLoader.item.queueCommand([__PYTHON__, __SCRIPT__, "middle", __MARKERS__])
    }
    Timer {
        interval: 250; running: true; repeat: false
        onTriggered: configLoader.item.queueCommand([__PYTHON__, __SCRIPT__, "latest", __MARKERS__])
    }
    Timer { interval: 300; running: true; repeat: false; onTriggered: configLoader.active = false }
    Timer { interval: 1500; running: true; repeat: false; onTriggered: console.log("THEME_COALESCE_CHECK") }
}
'''
            main.write_text(qml.replace("__PYTHON__", json.dumps(shutil.which("python3")))
                             .replace("__SCRIPT__", json.dumps(str(theme_script)))
                             .replace("__MARKERS__", json.dumps(str(marker_dir))))
            output = self.run_until_marker(base, main, "THEME_COALESCE_CHECK", timeout=5)
            self.assertIn("THEME_COALESCE_CHECK", output, output)
            self.assertTrue((marker_dir / "running.done").exists(), output)
            self.assertTrue((marker_dir / "latest.done").exists(), output)
            self.assertFalse((marker_dir / "middle.done").exists(), output)

    def test_command_failure_remains_visible_in_queue_status(self):
        with tempfile.TemporaryDirectory(prefix="rice-theme-command-error-") as directory:
            base = Path(directory)
            self.prepare_shell_tree(base)
            failing_command = base / "fail.py"
            failing_command.write_text("raise SystemExit(7)\n")
            main = base / "main.qml"
            qml = '''import QtQuick
import Quickshell
import "./dashboard"
import "./services"
ShellRoot {
    Loader { id: configLoader; active: true; sourceComponent: Config { } }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: configLoader.item.queueCommand([__PYTHON__, __FAIL__])
    }
    Timer {
        interval: 500; running: true; repeat: false
        onTriggered: console.log("THEME_ERROR_STATUS:" + ThemeCommandQueue.result)
    }
}
'''
            main.write_text(qml.replace("__PYTHON__", json.dumps(shutil.which("python3")))
                             .replace("__FAIL__", json.dumps(str(failing_command))))
            output = self.run_until_marker(base, main, "THEME_ERROR_STATUS:", timeout=4)
            self.assertIn("THEME_ERROR_STATUS:Command failed (exit 7)", output, output)

    def test_shell_reload_waits_for_running_command_after_config_closes(self):
        with tempfile.TemporaryDirectory(prefix="rice-theme-reload-queue-") as directory:
            base = Path(directory)
            self.prepare_shell_tree(base)
            marker = base / "completion.marker"
            slow_command = base / "slow_command.py"
            slow_command.write_text(
                "from pathlib import Path\n"
                "import sys, time\n"
                "time.sleep(0.45)\n"
                "Path(sys.argv[1]).write_text('completed')\n"
            )
            main = base / "main.qml"
            qml = '''import QtQuick
import Quickshell
import "./dashboard"
import "./services"
ShellRoot {
    id: root
    property int reloadCount: 0
    Loader { id: configLoader; active: true; sourceComponent: Config { } }
    Connections {
        target: ThemeCommandQueue
        function onReloadRequested() { root.reloadCount += 1; }
    }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: configLoader.item.queueCommand([__PYTHON__, __SLOW__, __MARKER__])
    }
    Timer {
        interval: 150; running: true; repeat: false
        onTriggered: configLoader.item.reloadShell()
    }
    Timer { interval: 250; running: true; repeat: false; onTriggered: configLoader.active = false }
    Timer {
        interval: 900; running: true; repeat: false
        onTriggered: console.log("THEME_RELOAD_COUNT:" + root.reloadCount)
    }
}
'''
            main.write_text(qml.replace("__PYTHON__", json.dumps(shutil.which("python3")))
                             .replace("__SLOW__", json.dumps(str(slow_command)))
                             .replace("__MARKER__", json.dumps(str(marker))))
            output = self.run_until_marker(base, main, "THEME_RELOAD_COUNT:", timeout=4)
            self.assertIn("THEME_RELOAD_COUNT:1", output, output)
            self.assertTrue(marker.exists(), output)


if __name__ == "__main__":
    unittest.main()
