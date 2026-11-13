"""Isolated native Quickshell regression checks for the tray context popup."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRAY_DIRECTORY = ROOT / "config/quickshell/rice-shell/bar"


class TrayMenuBehaviorTest(unittest.TestCase):
    def test_popup_dismissal_releases_references_and_can_reopen(self):
        source = '''
import QtQuick
import Quickshell
import "@@TRAY_DIRECTORY@@" as Tray

ShellRoot {
    FloatingWindow {
        id: anchorWindow
        width: 320
        height: 40
        visible: true
    }

    Tray.TrayContextMenu {
        id: popup
        anchorWindow: anchorWindow
    }

    Timer {
        interval: 150
        running: true
        repeat: false
        onTriggered: {
            function check(ok, message) {
                if (!ok) {
                    console.error("TRAY_TEST_FAIL: " + message);
                    Qt.quit();
                    throw Error("TRAY_TEST_FAIL: " + message);
                }
            }
            function findFlickable(item) {
                if (!item) return null;
                if (item.contentY !== undefined && item.contentHeight !== undefined
                        && item.interactive !== undefined) return item;
                const children = item.children || [];
                for (let i = 0; i < children.length; i++) {
                    const found = findFlickable(children[i]);
                    if (found) return found;
                }
                return null;
            }
            check(!popup.visible, "popup should initially be hidden");
            check(popup.grabFocus, "outside click must be able to dismiss popup");
            popup.openMenu(null, 24, 16);
            check(!popup.visible, "null menu must not open an empty popup");

            popup.anchorWindow = null;
            popup.openMenu({ sentinel: "noAnchor" }, 24, 16);
            check(!popup.visible, "missing anchor must not open an orphan popup");
            popup.anchorWindow = anchorWindow;
            popup.openMenu({ sentinel: "validHandle" }, 24, 16);
            check(popup.visible, "openMenu must display popup");

            const scrollArea = findFlickable(popup.contentItem);
            check(scrollArea !== null, "popup must contain a scrollable menu area");
            scrollArea.contentY = 45;
            check(scrollArea.contentY > 0, "scroll position can be retained");
            popup.openMenu({ sentinel: "anotherHandle" }, 48, 16);
            check(scrollArea.contentY === 0, "opening another menu must start at its first item");
            scrollArea.contentY = 45;
            popup.menuPath = [{ text: "submenu" }];
            check(scrollArea.contentY === 0, "entering a submenu must start at its first item");

            // Quickshell grabFocus sets visible=false when the user clicks outside.
            popup.menuHandle = { sentinel: "handle" };
            popup.menuPath = [{ text: "submenu" }];
            popup.visible = false;
            check(!popup.visible, "outside-dismissal visibility transition");
            check(popup.menuHandle === null, "dismissal must release menu handle");
            check(popup.menuPath.length === 0, "dismissal must release submenu path");

            popup.openMenu({ sentinel: "nextHandle" }, 48, 16);
            check(popup.visible, "popup must reopen after dismissal");
            check(popup.menuPath.length === 0, "reopen must start at root menu");
            popup.openMenu(null, 48, 16);
            check(!popup.visible && popup.menuHandle === null && popup.menuPath.length === 0,
                  "invalid new menu must dismiss the previous menu");
            popup.openMenu({ sentinel: "finalHandle" }, 64, 16);
            check(popup.visible, "popup must reopen after invalid menu");
            popup.closeMenu();
            check(!popup.visible && popup.menuHandle === null && popup.menuPath.length === 0,
                  "explicit close must release all references");
            console.log("TRAY_TEST_PASS");
            Qt.quit();
        }
    }
}
'''.replace("@@TRAY_DIRECTORY@@", TRAY_DIRECTORY.as_uri())

        with tempfile.TemporaryDirectory(prefix="tray-popup-test-") as directory:
            qml_path = Path(directory) / "shell.qml"
            qml_path.write_text(source, encoding="utf-8")
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
            try:
                result = subprocess.run(
                    ["quickshell", "--path", str(qml_path), "--no-color"],
                    capture_output=True, text=True, env=env, timeout=12,
                    check=False,
                )
            except FileNotFoundError:
                self.skipTest("quickshell binary unavailable")

        output = result.stdout + "\n" + result.stderr
        self.assertEqual(result.returncode, 0, output[-1500:])
        self.assertIn("TRAY_TEST_PASS", output, output[-1500:])
        self.assertNotIn("TRAY_TEST_FAIL", output, output[-1500:])


if __name__ == "__main__":
    unittest.main()
