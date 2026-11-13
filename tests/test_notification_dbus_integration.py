"""Exercise the real Quickshell NotificationServer on an isolated D-Bus bus.

The test copies Notifications.qml unchanged in behavior, adding only diagnostic
logs to observe real Notification objects. No user session bus or shell is used.
"""

import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/overlays/Notifications.qml"
SHELL_SOURCE = SOURCE.parent.parent / "shell.qml"
REQUIRED_TOOLS = ("dbus-run-session", "quickshell", "gdbus")


def _make_config(directory):
    for folder in ("overlays", "services", "theme", "runtime", "config", "cache"):
        (directory / folder).mkdir()
    (directory / "runtime").chmod(0o700)

    source = SOURCE.read_text()
    tracked = "notif.tracked = true;"
    expiry = """if (expiration.notification && expiration.notification.tracked)
                        expiration.notification.expire();"""
    if source.count(tracked) != 1 or source.count(expiry) != 1:
        raise AssertionError("Notifications.qml lifecycle hooks changed; update integration probes")
    source = source.replace(
        tracked,
        tracked + '\n            console.log("DBUS_PROBE_TRACKED", notif.summary, notif.tracked, notif.expireTimeout, notif.lastGeneration);'
        + '\n            Qt.callLater(() => console.log("DBUS_PROBE_STILL_TRACKED", notif.summary, notif.tracked));',
        1,
    ).replace(
        expiry,
        """if (expiration.notification && expiration.notification.tracked) {
                        console.log("DBUS_PROBE_EXPIRE", expiration.notification.summary);
                        expiration.notification.expire();
                    }""",
        1,
    )
    (directory / "overlays/Notifications.qml").write_text(source)
    (directory / "services/qmldir").write_text("singleton DesktopControls 1.0 DesktopControls.qml\n")
    (directory / "services/DesktopControls.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { property string lastSummary: ""; '
        'property string lastBody: ""; property bool doNotDisturb: false; '
        'function recordNotification(summary, body, appName, appIcon) {} }\n'
    )
    (directory / "theme/Stub.qml").write_text("import QtQuick\nQtObject {}\n")
    shell_source = SHELL_SOURCE.read_text()
    ipc_start = shell_source.index("        function islandNotification(")
    ipc_end = shell_source.index("\n\n        function toggleLauncher", ipc_start)
    island_dispatch = shell_source[ipc_start:ipc_end]
    loader_match = re.search(
        r"^    Loader \{\n        id: notificationLoader\n.*?^    \}",
        shell_source, re.MULTILINE | re.DOTALL,
    )
    if loader_match is None:
        raise AssertionError("Missing production notification Loader wiring")
    notification_loader = loader_match.group(0)
    (directory / "shell.qml").write_text(
        """import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property var islandInstances: [mockIsland]
    function instanceOnScreen(instances: var, requestedScreen: var): var { return instances.length ? instances[0] : null; }
    Item {
        id: mockIsland
        function triggerNotification(summary: string, body: string, app: string, icon: string): void {
            console.log("DBUS_PROBE_FORWARD", summary);
        }
    }

    IpcHandler {
        id: riceIpc
        target: "notification_regression"
        function reloadShell(): void { Quickshell.reload(false); }
""" + island_dispatch + "\n    }\n\n" + notification_loader + "\n" + """

    Component.onCompleted: console.log("DBUS_PROBE_READY")
}
"""
    )
    return directory / "shell.qml"


class _LineCapture:
    def __init__(self):
        self.lines = []
        self.pending = queue.Queue()

    def watch(self, process, label):
        def reader():
            for line in process.stdout:
                self.pending.put(label + ": " + line.rstrip())

        threading.Thread(target=reader, daemon=True).start()

    def until(self, predicate, timeout, description, *processes):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate(self.lines):
                return
            for process in processes:
                if process.poll() is not None:
                    raise AssertionError(f"{description}: process exited {process.returncode}; {self.tail()}")
            try:
                self.lines.append(self.pending.get(timeout=0.08))
            except queue.Empty:
                pass
        raise AssertionError(f"Timed out waiting for {description}; {self.tail()}")

    def drain(self, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                self.lines.append(self.pending.get(timeout=0.06))
            except queue.Empty:
                pass

    def tail(self):
        return "\n".join(self.lines[-28:])


def _call(env, *args):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=4)
    if result.returncode:
        raise AssertionError(f"{' '.join(args)}: {result.stderr[-500:]}")
    return result.stdout.strip()


def _notify(env, summary, timeout_ms):
    output = _call(
        env, "gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
        "--object-path", "/org/freedesktop/Notifications", "--method",
        "org.freedesktop.Notifications.Notify", "RegressionTest", "0", "", summary,
        "body", "[]", "{}", f"int32 {timeout_ms}",
    )
    match = re.fullmatch(r"\(uint32 (\d+),\)", output)
    if not match:
        raise AssertionError(f"Unexpected D-Bus Notify reply: {output}")
    return int(match.group(1))


def _integration_child():
    # Called only through dbus-run-session, never via the user's own bus.
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise AssertionError("No private D-Bus session address")
    with tempfile.TemporaryDirectory(prefix="notification-dbus-e2e-") as tmp:
        directory = Path(tmp)
        shell_path = _make_config(directory)
        env = os.environ.copy()
        for name in ("WAYLAND_DISPLAY", "QT_WAYLAND_DISPLAY", "DISPLAY", "QS_CONFIG_PATH"):
            env.pop(name, None)
        env.update(
            QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
            QSG_RHI_BACKEND="software", NO_AT_BRIDGE="1",
            XDG_RUNTIME_DIR=str(directory / "runtime"),
            XDG_CONFIG_HOME=str(directory / "config"),
            XDG_CACHE_HOME=str(directory / "cache"),
        )
        capture = _LineCapture()
        shell = subprocess.Popen(
            ["quickshell", "--path", str(shell_path), "--no-color"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        capture.watch(shell, "shell")
        monitor = None
        try:
            capture.until(lambda lines: any("DBUS_PROBE_READY" in line for line in lines),
                          5, "isolated shell startup", shell)
            _call(env, "gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                  "--object-path", "/org/freedesktop/Notifications", "--method",
                  "org.freedesktop.Notifications.GetServerInformation")

            monitor = subprocess.Popen(
                ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.Notifications",
                 "--object-path", "/org/freedesktop/Notifications"],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            capture.watch(monitor, "dbus")
            capture.until(lambda lines: any("Monitoring signals" in line for line in lines),
                          3, "D-Bus signal monitor", shell, monitor)

            started = time.monotonic()
            expiry_id = _notify(env, "expiry-probe", 1000)
            capture.until(lambda lines: any("DBUS_PROBE_TRACKED expiry-probe true" in line for line in lines),
                          3, "notification tracked by real server", shell)
            tracked_line = next(line for line in capture.lines
                                 if "DBUS_PROBE_TRACKED expiry-probe true" in line)
            if not re.search(r"DBUS_PROBE_TRACKED expiry-probe true 1000(?:\.0)?(?:\s|$)", tracked_line):
                raise AssertionError(f"Quickshell 0.3.2 should expose the 1000ms D-Bus timeout; got: {tracked_line}")
            capture.until(lambda lines: any("DBUS_PROBE_STILL_TRACKED expiry-probe true" in line for line in lines),
                          3, "notification remains tracked on the next event-loop tick", shell)
            capture.until(lambda lines: any("DBUS_PROBE_EXPIRE expiry-probe" in line for line in lines),
                          3, "one-second notification timeout", shell)
            capture.until(
                lambda lines: any("NotificationClosed" in line and
                                  f"uint32 {expiry_id}, uint32 1" in line for line in lines),
                3, "D-Bus NotificationClosed with reason expired", shell, monitor,
            )
            if time.monotonic() - started < 0.75:
                raise AssertionError("Notification expired before the requested one-second timeout")

            never_expiry_id = _notify(env, "never-expiry-probe", 0)
            capture.until(lambda lines: any("DBUS_PROBE_TRACKED never-expiry-probe true" in line for line in lines),
                          3, "non-expiring notification tracked by real server", shell)
            never_expiry_line = next(line for line in capture.lines
                                     if "DBUS_PROBE_TRACKED never-expiry-probe true" in line)
            if not re.search(r"DBUS_PROBE_TRACKED never-expiry-probe true 0(?:\.0)?(?:\s|$)", never_expiry_line):
                raise AssertionError(f"D-Bus timeout 0 must remain zero; got: {never_expiry_line}")

            default_started = time.monotonic()
            default_id = _notify(env, "default-expiry-probe", -1)
            capture.until(lambda lines: any("DBUS_PROBE_TRACKED default-expiry-probe true" in line for line in lines),
                          3, "default-timeout notification tracked", shell)
            default_line = next(line for line in capture.lines
                                if "DBUS_PROBE_TRACKED default-expiry-probe true" in line)
            if not re.search(r"DBUS_PROBE_TRACKED default-expiry-probe true -1(?:\.0)?(?:\s|$)", default_line):
                raise AssertionError(f"D-Bus timeout -1 must remain negative; got: {default_line}")
            capture.drain(5.3)
            if not any("DBUS_PROBE_EXPIRE default-expiry-probe" in line for line in capture.lines):
                raise AssertionError("Default -1 timeout did not expire after five seconds")
            if not any("NotificationClosed" in line and
                       f"uint32 {default_id}, uint32 1" in line for line in capture.lines):
                raise AssertionError("Default -1 timeout did not emit the expired reason")
            if time.monotonic() - default_started < 4.5:
                raise AssertionError("Default -1 notification expired too early")
            if any("DBUS_PROBE_EXPIRE never-expiry-probe" in line for line in capture.lines):
                raise AssertionError("A notification with expire_timeout=0 was expired by the local timer")
            if any("NotificationClosed" in line and
                   f"uint32 {never_expiry_id}, uint32 1" in line for line in capture.lines):
                raise AssertionError("A notification with expire_timeout=0 emitted the expired reason")
            _call(env, "gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                  "--object-path", "/org/freedesktop/Notifications", "--method",
                  "org.freedesktop.Notifications.CloseNotification", str(never_expiry_id))
            capture.until(
                lambda lines: any("NotificationClosed" in line and
                                  f"uint32 {never_expiry_id}, uint32 3" in line for line in lines),
                3, "manual close of a non-expiring notification", shell, monitor,
            )

            reload_id = _notify(env, "reload-probe", 8000)
            capture.until(lambda lines: any("DBUS_PROBE_TRACKED reload-probe true" in line for line in lines),
                          3, "notification tracked before reload", shell)
            _call(env, "quickshell", "--path", str(shell_path), "ipc", "--pid", str(shell.pid),
                  "call", "notification_regression", "reloadShell")
            capture.until(lambda lines: sum("DBUS_PROBE_READY" in line for line in lines) >= 2,
                          4, "actual Quickshell reload", shell)
            capture.until(lambda lines: sum("DBUS_PROBE_TRACKED reload-probe" in line for line in lines) >= 2,
                          4, "tracked notification carried over reload", shell)
            carried = [line for line in capture.lines if "DBUS_PROBE_TRACKED reload-probe" in line]
            if len(carried) != 2 or not carried[1].endswith("true"):
                raise AssertionError("Reloaded notification must be marked lastGeneration:\n" + capture.tail())
            if sum("DBUS_PROBE_FORWARD reload-probe" in line for line in capture.lines) != 1:
                raise AssertionError("Reload must not repeat the notification popup:\n" + capture.tail())
            if any("NotificationClosed" in line and f"uint32 {reload_id}," in line
                   for line in capture.lines):
                raise AssertionError("Reload unexpectedly closed an active notification:\n" + capture.tail())

            _notify(env, "post-reload-probe", 3000)
            capture.until(lambda lines: any("DBUS_PROBE_TRACKED post-reload-probe true" in line for line in lines),
                          3, "new D-Bus notification after reload", shell)
            capture.until(lambda lines: any("DBUS_PROBE_FORWARD post-reload-probe" in line for line in lines),
                          3, "production IPC forwards a new notification", shell)
            if sum("DBUS_PROBE_FORWARD reload-probe" in line for line in capture.lines) != 1:
                raise AssertionError("Old notification popup replayed after reload:\n" + capture.tail())
            if sum("DBUS_PROBE_FORWARD post-reload-probe" in line for line in capture.lines) != 1:
                raise AssertionError("Notification forwarded more than once through island IPC:\n" + capture.tail())
        except Exception as error:
            print(f"INTEGRATION_ERROR: {error}; trace:\n{capture.tail()}", file=sys.stderr)
            return 1
        finally:
            for process in (monitor, shell):
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=2)
    return 0


class NotificationDbusIntegrationTest(unittest.TestCase):
    def test_real_dbus_server_tracking_expiration_and_reload(self):
        missing = [binary for binary in REQUIRED_TOOLS if shutil.which(binary) is None]
        if missing:
            self.skipTest("Cannot run offscreen D-Bus integration: missing " + ", ".join(missing))
        env = os.environ.copy()
        for key in ("DBUS_SESSION_BUS_ADDRESS", "DBUS_STARTER_ADDRESS", "DBUS_STARTER_BUS_TYPE"):
            env.pop(key, None)
        result = subprocess.run(
            ["dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()), "--child"],
            env=env, capture_output=True, text=True, timeout=18,
        )
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-3500:])


if __name__ == "__main__":
    if sys.argv[1:] == ["--child"]:
        sys.exit(_integration_child())
    unittest.main()
