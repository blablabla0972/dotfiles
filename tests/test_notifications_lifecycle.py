"""Exercise the real Notifications.qml handlers in an isolated Qt QML engine."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/overlays/Notifications.qml"


def _write_harness(directory):
    source = SOURCE.read_text()
    for dependency in (
        "import Quickshell\n",
        "import Quickshell.Wayland\n",
        "import Quickshell.Services.Notifications\n",
        'import "../theme"\n',
        'import "../services"\n',
    ):
        assert dependency in source, f"Unexpected notification import: {dependency}"
        source = source.replace(dependency, "", 1)

    assert source.count("NotificationServer {") == 1
    assert source.count("expiration.destroy();") == 1
    source = source.replace("NotificationServer {", "MockNotificationServer {", 1)
    source = source.replace("DesktopControls.", "root.mockControls.")
    # Observe the actual destruction call, including reentrancy via onClosed.
    source = source.replace("expiration.destroy();", "root.destroyCalls++; expiration.destroy();")
    source = source.replace(
        "    signal notificationReceived(",
        """    property int destroyCalls: 0
    property var mockControls: controls
    property var notificationServer: server
    function inject(notification) { server.deliver(notification); }
    QtObject {
        id: controls
        property string lastSummary: ""
        property string lastBody: ""
        property bool doNotDisturb: false
        property var notificationHistory: []
        function recordNotification(summary, body, appName, appIcon) {
            notificationHistory = [{ summary: summary, body: body, appName: appName }].concat(notificationHistory);
        }
    }

    signal notificationReceived(""",
        1,
    )
    (directory / "Instrumented.qml").write_text(source)
    (directory / "MockState.js").write_text(".pragma library\nvar lastNotification = null;\n")
    (directory / "MockNotificationServer.qml").write_text(
        """import QtQuick
import "MockState.js" as State
QtObject {
    signal notification(var notification)
    property bool keepOnReload: true
    property bool bodySupported: false
    property bool bodyMarkupSupported: false
    property bool actionsSupported: false
    function deliver(n) { State.lastNotification = n; notification(n); }
    Component.onCompleted: {
        if (keepOnReload && State.lastNotification)
            Qt.callLater(() => {
                State.lastNotification.lastGeneration = true;
                notification(State.lastNotification);
            });
    }
}
"""
    )
    (directory / "FakeNotification.qml").write_text(
        """import QtQuick
QtObject {
    signal closed()
    property bool tracked: false
    property bool lastGeneration: false
    property real expireTimeout: 1000
    property string summary: "Summary"
    property string body: "Body"
    property string appName: "App"
    property string appIcon: "icon"
    property int expireCalls: 0
    function expire() { expireCalls++; tracked = false; closed(); }
    function close() { tracked = false; closed(); }
}
"""
    )


class NotificationLifecycleTest(unittest.TestCase):
    def _run_qml(self, scenario):
        with tempfile.TemporaryDirectory(prefix="notification-qml-") as tmp:
            directory = Path(tmp)
            _write_harness(directory)
            (directory / "Main.qml").write_text(
                """import QtQuick
Item {
    id: driver
    property var view
    property var notification
    property int received: 0
    Component { id: views; Instrumented {} }
    Component { id: notifications; FakeNotification {} }
    function openView() {
        let v = views.createObject(driver);
        if (!v) fail("could not construct notification view");
        v.notificationReceived.connect(() => received++);
        return v;
    }
    function newNotification(seconds) {
        return notifications.createObject(driver, { expireTimeout: seconds });
    }
    function fail(message) { console.error("LIFECYCLE_FAIL: " + message); Qt.exit(1); throw new Error(message); }
    function check(condition, message) { if (!condition) fail(message); }
    function later(ms, fn) {
        let timer = Qt.createQmlObject('import QtQuick; Timer { repeat: false }', driver);
        timer.interval = ms;
        timer.triggered.connect(() => { fn(); timer.destroy(); });
        timer.start();
    }
    function pass() { Qt.exit(73); }
    Component.onCompleted: later(10, () => {
"""
                + scenario
                + "\n    });\n}\n"
            )
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NO_AT_BRIDGE="1")
            run = subprocess.run(
                ["qml6", "-f", str(directory / "Main.qml"), "--quit-after", "4000"],
                env=env,
                text=True,
                capture_output=True,
                timeout=7,
                check=False,
            )
            self.assertEqual(
                run.returncode, 73,
                f"QML exit {run.returncode}: " + (run.stdout + run.stderr)[-2000:],
            )

    def test_received_notification_is_tracked_and_respects_dnd(self):
        self._run_qml("""
        view = openView();
        notification = newNotification(2000);
        view.inject(notification);
        check(notification.tracked, "notification must be retained");
        check(received === 1, "notification signal must be forwarded");
        check(view.mockControls.lastBody === "Body", "summary/body must be updated");
        check(view.mockControls.notificationHistory.length === 1, "new alert must enter history");
        view.mockControls.doNotDisturb = true;
        view.inject(newNotification(2000));
        check(received === 1, "DND must suppress popup signals");
        check(view.mockControls.notificationHistory.length === 2, "DND must preserve notification history");
        pass();
""")

    def test_expire_timeout_is_milliseconds_and_destroys_timer_once(self):
        self._run_qml("""
        view = openView(); notification = newNotification(1000); view.inject(notification);
        later(400, () => check(notification.expireCalls === 0, "expired before one second"));
        later(1300, () => {
            check(notification.expireCalls === 1, "must expire after one second");
            check(view.destroyCalls === 1, "timer.destroy called more than once");
            pass();
        });
""")

    def test_closed_notification_releases_timer(self):
        self._run_qml("""
        view = openView(); notification = newNotification(1000); view.inject(notification);
        later(100, () => notification.close());
        later(300, () => check(view.destroyCalls === 1, "closed timer not released promptly"));
        later(1300, () => {
            check(notification.expireCalls === 0, "closed notification expired again");
            check(view.destroyCalls === 1, "closed timer must be destroyed once");
            pass();
        });
""")

    def test_reload_preserves_old_notification_without_reopening_popup(self):
        self._run_qml("""
        view = openView(); notification = newNotification(1000); view.inject(notification);
        check(received === 1, "initial event missing");
        view.destroy();
        later(100, () => {
            view = openView();
        });
        later(1300, () => {
            check(received === 1, "notification replayed on reload");
            check(view.mockControls.notificationHistory.length === 1, "reload must restore retained alert history");
            check(view.notificationServer.keepOnReload === true, "reload should retain tracked notifications");
            check(notification.expireCalls === 1, "reloaded notification should still expire");
            check(view.destroyCalls === 1, "reloaded timer should be disposed after expiry");
            pass();
        });
""")


if __name__ == "__main__":
    unittest.main()
