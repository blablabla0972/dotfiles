"""Exercise the production status pages in an isolated Quickshell QML host."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = ROOT / "config/quickshell/rice-shell/dashboard"
SERVICES = ROOT / "config/quickshell/rice-shell/services"
RESULT_PREFIX = "STATUS_PAGES_RESULT="


class DashboardStatusPagesRedesignTests(unittest.TestCase):
    def test_real_pages_keep_partial_telemetry_and_notification_states(self):
        quickshell = shutil.which("quickshell")
        if not quickshell:
            self.skipTest("Quickshell runtime is unavailable")

        with tempfile.TemporaryDirectory(prefix="status-pages-") as tmp:
            temp = Path(tmp)
            config = temp / "config"
            config.mkdir()
            harness = temp / "status-pages.qml"
            harness.write_text(
                f'''import QtQuick
import QtQuick.Window
import "{DASHBOARD.as_uri()}" as Pages
import "{SERVICES.as_uri()}" as Services

Window {{
    id: host
    visible: false
    width: 724
    height: 370

    Pages.System {{
        id: systemPage
        width: host.width
        height: host.height
        visible: false
        sample: ({{ cpu_pct: null }})
        cpuHistory: [null, 37, null]
    }}

    Pages.NotificationCenter {{
        id: alertsPage
        width: host.width
        height: host.height
        visible: false
    }}

    Component.onCompleted: Qt.callLater(function() {{
        systemPage.cpuHistory = [null, 37, null];
        const startsEmpty = !alertsPage.hasNotifications;
        const body = alertsPage.children[0].children[1];
        const emptyState = body.children[1];
        const emptyContent = emptyState.children[0];
        const emptyCenter = emptyContent.mapToItem(
            alertsPage, emptyContent.width / 2, emptyContent.height / 2);
        const emptyCentered = Math.abs(emptyCenter.x - alertsPage.width / 2) < 1;
        Services.DesktopControls.notificationHistory = [{{
            id: 41,
            appName: "Fixture app",
            appIcon: "",
            time: "12:34",
            summary: "Fixture summary",
            body: "Fixture body"
        }}];
        Services.DesktopControls.doNotDisturb = true;
        Qt.callLater(function() {{
            const populated = alertsPage.hasNotifications
                && alertsPage.notificationCount === 1
                && alertsPage.dndActive;
            Services.DesktopControls.clearNotificationHistory();
            Qt.callLater(function() {{
                console.log("{RESULT_PREFIX}" + JSON.stringify({{
                    pageWidth: systemPage.width,
                    columns: systemPage.layoutColumns,
                    cpuUnavailable: systemPage.cpuPct === null,
                    partialNullAccepted: systemPage.validSnapshot({{ cpu_pct: null }}),
                    historySamples: systemPage.cpuHistory.length,
                    startsEmpty: startsEmpty,
                    emptyCentered: emptyCentered,
                    populated: populated,
                    cleared: !alertsPage.hasNotifications
                        && alertsPage.notificationCount === 0
                }}));
                Qt.quit();
            }});
        }});
    }});
}}
''',
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "QT_QPA_PLATFORM": "offscreen",
                    "XDG_CONFIG_HOME": str(config),
                    "XDG_CACHE_HOME": str(temp / "cache"),
                    "XDG_DATA_HOME": str(temp / "data"),
                    "XDG_STATE_HOME": str(temp / "state"),
                }
            )
            result = subprocess.run(
                [quickshell, "--path", str(harness), "--no-duplicate"],
                env=env,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-4000:])
        self.assertNotIn("ReferenceError", output, output[-4000:])
        self.assertNotIn("TypeError", output, output[-4000:])
        payloads = [line.split(RESULT_PREFIX, 1)[1]
                    for line in output.splitlines() if RESULT_PREFIX in line]
        self.assertTrue(payloads, output[-4000:])
        state = json.loads(payloads[-1])
        self.assertEqual(state["columns"], 2, state)
        self.assertTrue(state["cpuUnavailable"])
        self.assertTrue(state["partialNullAccepted"])
        self.assertEqual(state["historySamples"], 3)
        self.assertTrue(state["startsEmpty"])
        self.assertTrue(state["emptyCentered"], state)
        self.assertTrue(state["populated"])
        self.assertTrue(state["cleared"])


if __name__ == "__main__":
    unittest.main()
