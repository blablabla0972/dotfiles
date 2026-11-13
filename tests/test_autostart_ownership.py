"""Exercise config-specific Quickshell startup and notification gating."""
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
START_SCRIPT = ROOT / "config/hypr/scripts/start-rice-shell.sh"
SHELL_QML = ROOT / "config/quickshell/rice-shell/shell.qml"


class AutostartOwnershipTest(unittest.TestCase):
    def make_stubs(self, base):
        stub_bin = base / "bin"
        stub_bin.mkdir()
        quickshell = stub_bin / "quickshell"
        quickshell.write_text('''#!/usr/bin/env bash
echo "quickshell $*" >> "$TRACE"
if [[ "${1:-}" == "list" ]]; then
    if [[ "${RICE_TEST_RUNNING:-0}" == "1" || -f "$TEST_STATE/started" ]]; then
        printf '[{"config_path":"%s/shell.qml"}]\n' "$3"
    else
        printf '[]\n'
    fi
    exit 0
fi
if [[ "${1:-}" == "ipc" ]]; then
    [[ "${RICE_TEST_HEALTH:-0}" == "1" || ( -f "$TEST_STATE/started" && "${RICE_TEST_START_MODE:-}" == "healthy" ) ]]
    exit $?
fi
if [[ "${RICE_TEST_START_MODE:-}" != "missing" ]]; then
    mkdir -p "$TEST_STATE"
    touch "$TEST_STATE/started"
fi
echo "notifications=${ENABLE_NOTIFICATIONS:-unset}" >> "$TRACE"
''')
        quickshell.chmod(0o755)
        noctalia = stub_bin / "noctalia"
        noctalia.write_text('#!/usr/bin/env bash\necho "noctalia $*" >> "$TRACE"\n')
        noctalia.chmod(0o755)
        pgrep = stub_bin / "pgrep"
        pgrep.write_text('#!/usr/bin/env bash\n[[ "${RICE_TEST_NOCTALIA_RUNNING:-0}" == "1" ]]\n')
        pgrep.chmod(0o755)
        sleep = stub_bin / "sleep"
        sleep.write_text('#!/usr/bin/env bash\nexit 0\n')
        sleep.chmod(0o755)
        return stub_bin

    def run_start(self, base, extra=None, path=None):
        config_home = base / "config"
        config_home.mkdir(exist_ok=True)
        state = base / "state"
        state.mkdir(exist_ok=True)
        trace = base / "trace"
        env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(config_home),
                   TRACE=str(trace), TEST_STATE=str(state),
                   PATH=path or (str(base / "bin") + os.pathsep + os.environ["PATH"]))
        env.update(extra or {})
        result = subprocess.run([shutil.which("bash"), str(START_SCRIPT)], env=env,
                                capture_output=True, text=True, timeout=5)
        return result, trace.read_text() if trace.exists() else ""

    def test_wallpaper_only_instance_does_not_block_rice_start(self):
        with tempfile.TemporaryDirectory(prefix="rice-autostart-wallpaper-") as directory:
            base = Path(directory)
            self.make_stubs(base)
            result, trace = self.run_start(base, {
                "RICE_TEST_WALLPAPER_RUNNING": "1",
                "RICE_TEST_START_MODE": "healthy",
            })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--no-duplicate --daemonize --path", trace)
        self.assertIn("/config/quickshell/rice-shell", trace)
        self.assertNotIn("noctalia", trace)

    def test_existing_rice_instance_is_health_checked_without_second_start(self):
        with tempfile.TemporaryDirectory(prefix="rice-autostart-existing-") as directory:
            base = Path(directory)
            self.make_stubs(base)
            result, trace = self.run_start(base, {
                "RICE_TEST_RUNNING": "1", "RICE_TEST_HEALTH": "1",
            })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("quickshell list", trace)
        self.assertIn("quickshell ipc", trace)
        self.assertNotIn("--no-duplicate", trace)
        self.assertNotIn("noctalia", trace)

    def test_failed_start_falls_back_only_after_rice_instance_is_gone(self):
        with tempfile.TemporaryDirectory(prefix="rice-autostart-fallback-") as directory:
            base = Path(directory)
            self.make_stubs(base)
            result, trace = self.run_start(base, {"RICE_TEST_START_MODE": "missing"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("noctalia -d", trace)

        with tempfile.TemporaryDirectory(prefix="rice-autostart-unhealthy-") as directory:
            base = Path(directory)
            self.make_stubs(base)
            result, trace = self.run_start(base, {"RICE_TEST_RUNNING": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("noctalia", trace)
        self.assertIn("sole notification owner", result.stderr)

    def test_notification_opt_out_reaches_rice_and_disables_fallback(self):
        with tempfile.TemporaryDirectory(prefix="rice-autostart-notifications-off-") as directory:
            base = Path(directory)
            self.make_stubs(base)
            result, trace = self.run_start(base, {
                "ENABLE_NOTIFICATIONS": "0", "RICE_TEST_START_MODE": "missing",
            })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("notifications=0", trace)
        self.assertNotIn("noctalia", trace)

    def test_missing_quickshell_uses_noctalia_fallback(self):
        with tempfile.TemporaryDirectory(prefix="rice-autostart-missing-") as directory:
            base = Path(directory)
            stubs = self.make_stubs(base)
            no_quickshell = base / "fallback-bin"
            no_quickshell.mkdir()
            for name in ("noctalia", "pgrep", "sleep"):
                shutil.copyfile(stubs / name, no_quickshell / name)
                (no_quickshell / name).chmod(0o755)
            (no_quickshell / "bash").symlink_to(shutil.which("bash"))
            result, trace = self.run_start(base, path=str(no_quickshell))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("noctalia -d", trace)

    @unittest.skipUnless(shutil.which("quickshell"), "Quickshell required")
    def test_notification_loader_defaults_on_and_can_be_disabled(self):
        source = SHELL_QML.read_text()
        match = re.search(r'Loader\s*\{\s*id: notificationLoader\s*\n\s*(active: [^\n]+)', source)
        self.assertIsNotNone(match, "production notification loader is missing its active binding")
        binding = match.group(1)
        for setting, expected in ((None, "true:true"), ("0", "false:false"), ("1", "true:true")):
            with self.subTest(setting=setting), tempfile.TemporaryDirectory(prefix="rice-notification-gate-") as directory:
                base = Path(directory)
                main = base / "main.qml"
                main.write_text('''import QtQuick
import Quickshell
ShellRoot {
    Loader {
        id: notificationLoader
        __BINDING__
        sourceComponent: Component { Item { } }
    }
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: console.log("NOTIFICATION_GATE:" + notificationLoader.active
            + ":" + (notificationLoader.item !== null))
    }
}
'''.replace("__BINDING__", binding))
                runtime = base / "runtime"
                runtime.mkdir(mode=0o700)
                env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / "config"),
                           XDG_STATE_HOME=str(base / "state"), XDG_RUNTIME_DIR=str(runtime),
                           QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
                if setting is None:
                    env.pop("ENABLE_NOTIFICATIONS", None)
                else:
                    env["ENABLE_NOTIFICATIONS"] = setting
                for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                    env.pop(name, None)
                process = subprocess.Popen(["quickshell", "--path", str(main), "--no-color"],
                                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                           text=True, bufsize=1)
                output = ""
                deadline = time.monotonic() + 3
                try:
                    while time.monotonic() < deadline:
                        ready, _, _ = select.select([process.stdout], [], [], 0.1)
                        if not ready:
                            if process.poll() is not None:
                                break
                            continue
                        line = process.stdout.readline()
                        output += line
                        if "NOTIFICATION_GATE:" in line:
                            break
                finally:
                    process.terminate()
                    process.wait(timeout=2)
                    process.stdout.close()
                self.assertIn("NOTIFICATION_GATE:" + expected, output, output)


if __name__ == "__main__":
    unittest.main()
