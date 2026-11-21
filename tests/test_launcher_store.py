"""Exercise launcher persistence through Quickshell's real QML runtime."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "config/quickshell/rice-shell/launcher"


@unittest.skipUnless(shutil.which("qs") and os.environ.get("WAYLAND_DISPLAY"),
                     "requires Quickshell and a live Wayland session")
class LauncherStoreTests(unittest.TestCase):
    def test_deduplicates_orders_reloads_and_recovers_from_malformed_json(self):
        with tempfile.TemporaryDirectory(prefix="launcher-store-") as temp:
            base = Path(temp)
            state = base / "state"
            state.mkdir()
            store_path = state / "launcher.json"
            malformed_path = state / "malformed.json"
            malformed_path.write_text("{broken", encoding="utf-8")
            (base / "launcher").symlink_to(LAUNCHER, target_is_directory=True)

            source = '''
import QtQuick
import Quickshell
import "./launcher" as StoreModule

ShellRoot {
    id: root
    StoreModule.LauncherStore { id: store; path: STORE_PATH }
    StoreModule.LauncherStore { id: malformed; path: MALFORMED_PATH }

    function assert(ok, message) {
        if (!ok) throw new Error(message);
    }

    function fail(error) {
        console.error("LAUNCHER_STORE_FAIL: " + error);
        Qt.exit(1);
    }

    Timer {
        id: mutate
        interval: 100
        running: true
        onTriggered: {
            try {
                if (TEST_MODE === "write") {
                    store.toggleFavorite("app-a");
                    store.toggleFavorite("app-b");
                    store.toggleFavorite("app-a");
                    store.toggleFavorite("app-a");
                    store.recordLaunch("app-a");
                    store.recordLaunch("app-b");
                    store.recordLaunch("app-a");
                    store.recordCalculation("1+1", "2");
                    store.recordCalculation("2+2", "4");
                    store.recordCalculation("1+1", "2");

                    root.assert(JSON.stringify(store.favorites) === JSON.stringify(["app-b", "app-a"]),
                                "favorite toggle order or uniqueness");
                    root.assert(JSON.stringify(store.recents) === JSON.stringify(["app-a", "app-b"]),
                                "recent launches must be newest first and unique");
                    root.assert(store.calculations.length === 2
                                && store.calculations[0].expression === "1+1"
                                && store.calculations[1].expression === "2+2",
                                "calculations must be newest first and deduplicated");
                    persist.start();
                } else {
                    root.assert(JSON.stringify(store.favorites) === JSON.stringify(["app-b", "app-a"]),
                                "favorites did not persist");
                    root.assert(JSON.stringify(store.recents) === JSON.stringify(["app-a", "app-b"]),
                                "recents did not persist");
                    root.assert(store.calculations.length === 2
                                && store.calculations[0].expression === "1+1"
                                && store.calculations[0].value === "2"
                                && store.calculations[1].expression === "2+2"
                                && store.calculations[1].value === "4",
                                "calculations did not persist");
                    root.assert(malformed.favorites.length === 0
                                && malformed.recents.length === 0
                                && malformed.calculations.length === 0,
                                "malformed JSON must load safe empty lists");
                    console.log("LAUNCHER_STORE_READ_PASS");
                    Qt.quit();
                }
            } catch (error) {
                root.fail(error);
            }
        }
    }

    Timer {
        id: persist
        interval: 200
        onTriggered: {
            try {
                console.log("LAUNCHER_STORE_WRITE_PASS");
                Qt.quit();
            } catch (error) {
                root.fail(error);
            }
        }
    }
}
'''
            source = source.replace("STORE_PATH", json.dumps(str(store_path)))
            source = source.replace("MALFORMED_PATH", json.dumps(str(malformed_path)))

            env = os.environ.copy()
            env["XDG_STATE_HOME"] = str(state)
            env["XDG_CONFIG_HOME"] = str(base / "config")
            env["XDG_CACHE_HOME"] = str(base / "cache")
            for mode in ("write", "read"):
                qml = base / f"{mode}-test.qml"
                qml.write_text(source.replace("TEST_MODE", json.dumps(mode)), encoding="utf-8")
                result = subprocess.run(["qs", "--no-color", "-p", str(qml)],
                                        capture_output=True, text=True, timeout=12, env=env)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output[-3000:])
                self.assertIn(f"LAUNCHER_STORE_{mode.upper()}_PASS", output, output[-3000:])
                self.assertNotIn("LAUNCHER_STORE_FAIL", output)
            self.assertTrue(store_path.is_file(), "store path must persist inside temporary state")


if __name__ == "__main__":
    unittest.main()
