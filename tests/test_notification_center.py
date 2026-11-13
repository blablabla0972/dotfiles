"""Smoke-test the actual Notifications tab using an isolated Qt QML engine."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CENTER_QML = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/dashboard/NotificationCenter.qml"


@unittest.skipUnless(shutil.which("qml6"), "qml6 required")
class NotificationCenterTest(unittest.TestCase):
    def test_history_list_and_clear_all(self):
        with tempfile.TemporaryDirectory(prefix="rice-notification-center-") as tmp:
            base = Path(tmp)
            for folder in ("dashboard", "theme", "services"):
                (base / folder).mkdir()

            source = CENTER_QML.read_text()
            self.assertEqual(source.count("textFormat: Text.PlainText"), 3)
            self.assertIn("id: notificationList", source)
            (base / "dashboard/NotificationCenter.qml").write_text(
                source.replace("    ColumnLayout {", "    readonly property alias probeCount: notificationList.count\n\n    ColumnLayout {", 1)
            )
            (base / "theme/qmldir").write_text("singleton Tokens 1.0 Tokens.qml\n")
            (base / "theme/Tokens.qml").write_text(
                "pragma Singleton\nimport QtQuick\nQtObject {\n" +
                "\n".join(f'property color {name}: "#8799ab"' for name in
                           ("surface", "surface_high", "surface_low", "outline", "accent",
                            "text_primary", "text_secondary")) + "\n}\n"
            )
            (base / "services/qmldir").write_text("singleton DesktopControls 1.0 DesktopControls.qml\n")
            (base / "services/DesktopControls.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property var notificationHistory: [
        { summary: "Mail", body: "One", appName: "Inbox", time: "12:00" },
        { summary: "Update", body: "Two", appName: "", time: "12:01" }
    ]
    function clearNotificationHistory() { notificationHistory = []; }
}
''')
            (base / "Main.qml").write_text('''import QtQuick
import "./dashboard"
import "./services"
Item {
    width: 760; height: 440
    NotificationCenter { id: center; anchors.fill: parent }
    Timer {
        interval: 160; running: true
        onTriggered: {
            if (center.probeCount !== 2) {
                console.error("NOTIFICATION_CENTER_FAIL: list did not display two alerts");
                Qt.exit(1);
                return;
            }
            DesktopControls.clearNotificationHistory();
            if (center.probeCount !== 0) {
                console.error("NOTIFICATION_CENTER_FAIL: clear did not empty the list");
                Qt.exit(1);
                return;
            }
            Qt.exit(73);
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            run = subprocess.run(["qml6", "-f", str(base / "Main.qml"), "--quit-after", "2000"],
                                 capture_output=True, text=True, env=env, timeout=5)
            self.assertEqual(run.returncode, 73, (run.stdout + run.stderr)[-1600:])
            self.assertNotIn("ReferenceError", run.stderr)
            self.assertNotIn("TypeError", run.stderr)


if __name__ == "__main__":
    unittest.main()
