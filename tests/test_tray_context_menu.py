"""Exercise tray popup geometry and app actions in an isolated offscreen shell."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "config/quickshell/rice-shell"

QML = r'''import QtQuick
import QtTest
import Quickshell
import "bar"

ShellRoot {
    id: root
    property bool quitTriggered: false
    property var rows
    property var repeater
    property int phase: 0
    FloatingWindow { id: bar; implicitWidth: 800; implicitHeight: 48; visible: true }
    TrayContextMenu { id: menu; anchorWindow: bar }
    TestCase { id: input; when: false }

    function check(condition, message) {
        if (!condition) {
            console.error("TRAY_REGRESSION: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function entry(text, enabled, callback) {
        return { text: text, enabled: enabled, isSeparator: false,
            hasChildren: false, icon: "", checkState: Qt.Unchecked, buttonType: QsMenuButtonType.None,
            triggered: callback || function() {} };
    }

    function indicator(index) {
        const row = root.repeater.itemAt(index);
        const layout = row.children[row.children.length - 1];
        return layout.children[layout.children.length - 1].text;
    }

    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.rows = menu.contentItem.children[0].children[0].contentItem.children[0];
                root.repeater = root.rows.children[root.rows.children.length - 1];
                // QsMenuEntry is uncreatable; inject app entries at its model boundary.
                root.repeater.model = [
                    root.entry("Open", true),
                    root.entry("Unavailable", false, function() { root.quitTriggered = true; }),
                    root.entry("Quit", true, function() { root.quitTriggered = true; })
                ];
                menu.clickX = 790;
                menu.clickY = 24;
                menu.visible = true;
                root.phase++;
            } else if (root.phase === 1) {
                root.check(menu.height >= root.rows.implicitHeight + 16,
                    "a 48px bar clips app actions: popup height=" + menu.height);
                root.check(menu.anchor.rect.y >= bar.height,
                    "menu must open below the bar");
                root.check(menu.anchor.rect.x + menu.width <= bar.width,
                    "rightmost tray menu leaves the screen");
                root.check(root.indicator(0) === "" && root.indicator(2) === "",
                    "ordinary app actions display checkbox indicators");
                input.mouseClick(menu.contentItem, 120, 59, Qt.LeftButton);
                root.check(!root.quitTriggered && menu.visible, "disabled app action was triggered");
                input.mouseClick(menu.contentItem, 120, 95, Qt.LeftButton);
                root.check(root.quitTriggered && !menu.visible, "Quit action did not trigger and close");
                root.check(menu.menuHandle === null && menu.menuPath.length === 0,
                    "closed menu retains its path");
                const many = [];
                for (let i = 0; i < 30; i++) many.push(root.entry("Action " + i, true));
                many[0].buttonType = QsMenuButtonType.CheckBox;
                many[1].buttonType = QsMenuButtonType.CheckBox;
                many[1].checkState = Qt.Checked;
                many[2].buttonType = QsMenuButtonType.CheckBox;
                many[2].checkState = Qt.PartiallyChecked;
                many[3].buttonType = QsMenuButtonType.RadioButton;
                many[4].buttonType = QsMenuButtonType.RadioButton;
                many[4].checkState = Qt.Checked;
                many[5].hasChildren = true;
                root.repeater.model = many;
                menu.visible = true;
                root.phase++;
            } else {
                const viewport = menu.contentItem.children[0].children[0];
                root.check(menu.height <= Math.min(520, bar.screen.height - bar.height - 16),
                    "long app menu exceeds available screen height");
                root.check(viewport.interactive && viewport.contentHeight > viewport.height,
                    "long app menu cannot scroll");
                root.check(root.indicator(0) === "□" && root.indicator(1) === "✓"
                    && root.indicator(2) === "−", "checkbox states are incorrect");
                root.check(root.indicator(3) === "○" && root.indicator(4) === "●",
                    "radio button states are incorrect");
                root.check(root.indicator(5) === "›", "submenu arrow is missing");
                menu.closeMenu();
                console.log("TRAY_REGRESSION_OK");
                Qt.quit();
            }
        }
    }
}
'''


class TrayContextMenuTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
    def test_app_actions_fit_below_a_short_bar(self):
        with tempfile.TemporaryDirectory(prefix="tray-menu-test-") as temporary:
            folder = Path(temporary)
            (folder / "bar").mkdir()
            (folder / "theme").mkdir()
            shutil.copy2(SHELL / "bar/TrayContextMenu.qml", folder / "bar")
            for name in ("Tokens.qml", "qmldir"):
                shutil.copy2(SHELL / "theme" / name, folder / "theme")
            (folder / "shell.qml").write_text(QML)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_STATE_HOME=str(folder / "state"))
            env.pop("WAYLAND_DISPLAY", None)
            env["QT_QPA_PLATFORMTHEME"] = ""
            result = subprocess.run(["qs", "-p", str(folder), "--no-color"],
                                    env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("TRAY_REGRESSION_OK", output, output)
            errors = [line for line in output.splitlines()
                      if "ERROR" in line or "TRAY_REGRESSION:" in line
                      or "TypeError" in line or "ReferenceError" in line]
            self.assertEqual(errors, [], "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
