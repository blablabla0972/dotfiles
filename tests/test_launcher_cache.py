"""Check the real QML launcher cache and preserve search/category results."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class LauncherSearchTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "requires Node.js")
    def test_rank_vietnamese_queries_and_use_desktop_categories(self):
        search = (Path(__file__).resolve().parents[1]
                  / "config/quickshell/rice-shell/launcher/LauncherSearch.js")
        source = r'''
const assert = require("node:assert/strict");
const apps = indexApps([
    { id: "note", name: "Ghi ch\u00fa", categories: ["Office"] },
    { id: "settings", name: "C\u00e0i \u0111\u1eb7t", categories: ["Settings"] },
    { id: "random", name: "Random", comment: "Cai dat network" },
    { id: "editor", name: "Image Editor", categories: ["Graphics"] },
    { id: "hidden", name: "cai dat", noDisplay: true }
]);
const ids = query => searchApps(apps, query).map(app => app.id);
assert.deepEqual(ids("CAI DAT"), ["settings", "random"]);
assert.deepEqual(ids("cdt"), ["settings"]);
assert.deepEqual(ids("ghi chu"), ["note"]);
assert.deepEqual(ids("garbage"), []);
assert.equal(matchesCategory(apps[2].app, "Internet"), false);
assert.equal(matchesCategory(apps[3].app, "Development"), false);
assert.equal(matchesCategory(apps[3].app, "Multimedia"), true);
const tieIds = Array.from({length: 45}, (_, i) => "app-" + String(i).padStart(2, "0"));
const tied = indexApps(tieIds.slice().reverse().map(id => ({id, name: "Notes"})));
assert.deepEqual(searchApps(tied, "notes").map(app => app.id), tieIds.slice(0, 40));
const browsers = indexApps([
    {id: "ice", name: "Firefox ESR"}, {id: "ff", name: "Firefox"},
    {id: "code", name: "Visual Studio Code"}, {id: "coc", name: "C\u1ed1c C\u1ed1c"}
]);
assert.equal(searchApps(browsers, "firefox", ["ice"], ["ice"], {ice: 100})[0].id, "ff");
assert.equal(searchApps(browsers, "fire fox")[0].id, "ff");
assert.equal(searchApps(browsers, "firifox")[0].id, "ff");
assert.equal(searchApps(browsers, "vscd")[0].id, "code");
assert.equal(searchApps(browsers, "coc coc")[0].id, "coc");
'''
        result = subprocess.run(["node", "-e", search.read_text() + source],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)


@unittest.skipUnless(shutil.which("qs") and os.environ.get("WAYLAND_DISPLAY"),
                     "requires Quickshell and a live Wayland session")
class LauncherCacheTests(unittest.TestCase):
    def test_cache_and_search_results(self):
        launcher = (Path(__file__).resolve().parents[1]
                    / "config/quickshell/rice-shell/launcher")
        source = '''
import QtQuick
import Quickshell
import "./launcher"
ShellRoot {
    LauncherStore { id: testStore }
    Launcher { id: launcher; targetScreen: Quickshell.screens[0]; store: testStore }
    Timer {
        interval: 150; running: true
        onTriggered: {
            var errors = [];
            var first = launcher.getZeroStateApps();
            if (first !== launcher.getZeroStateApps()) errors.push("zero-state cache miss");
            launcher.searchText = "rnote";
            launcher.searchText = "";
            if (first !== launcher.getZeroStateApps()) errors.push("typing invalidated zero state");
            testStore.recordLaunch("local-other");
            if (launcher.filteredApps[0]?.id !== "local-other") errors.push("recent app priority");
            testStore.toggleFavorite("local-settings");
            if (launcher.filteredApps[0]?.id !== "local-settings") errors.push("favorite priority");
            launcher.searchText = "cai dat";
            if (launcher.filteredApps.map(app => app.id).join() !== "local-settings,local-other")
                errors.push("native search ranking");
            launcher.selectedCategory = "Settings";
            if (launcher.filteredApps.map(app => app.id).join() !== "local-settings")
                errors.push("native category filter");
            launcher.searchText = "cdt";
            if (launcher.filteredApps.map(app => app.id).join() !== "local-settings")
                errors.push("native fuzzy matching");
            launcher.openContext(launcher.filteredApps[0]);
            if (launcher.filteredApps[2]?.name !== "Test desktop action") {
                errors.push("missing desktop action");
            } else {
                launcher.selectedIndex = 2;
                launcher.launchSelected();
            }
            launcher.closeContext();
            launcher.searchText = "unmatched-xyz";
            if (launcher.filteredApps.length) errors.push("unexpected result");
            launcher.searchText = "> echo test";
            if (launcher.filteredApps.length !== 1 || !launcher.filteredApps[0].isCommand
                || launcher.filteredApps[0].command !== "echo test") errors.push("command mode");
            console.log(errors.length ? "LAUNCHER_FAIL " + errors.join("; ") : "LAUNCHER_PASS");
            Qt.quit();
        }
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "launcher").symlink_to(launcher, target_is_directory=True)
            (root / "theme").symlink_to(launcher.parent / "theme", target_is_directory=True)
            path = root / "check.qml"
            path.write_text(source)
            desktop = root / "applications"
            desktop.mkdir()
            marker = root / "desktop-action-activated"
            for app, name, description, categories in (
                ("local-settings", "Cài đặt", "", "Settings"),
                ("local-other", "Other", "Cai dat", "Network"),
            ):
                (desktop / (app + ".desktop")).write_text(
                    f"[Desktop Entry]\nType=Application\nName={name}\n"
                    f"Comment={description}\nExec=true\nCategories={categories};\n"
                    + (f"Actions=Probe;\n\n[Desktop Action Probe]\nName=Test desktop action\n"
                       f"Exec=/usr/bin/touch {marker}\n" if app == "local-settings" else ""),
                    encoding="utf-8",
                )
            result = subprocess.run(["qs", "--no-color", "-p", str(path)],
                                    capture_output=True, text=True, timeout=15,
                                    env={**os.environ, "XDG_DATA_HOME": directory,
                                         "XDG_DATA_DIRS": directory, "XDG_STATE_HOME": directory})
            for _ in range(20):
                if marker.exists():
                    break
                time.sleep(0.05)
            action_launched = marker.exists()
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-3000:])
        self.assertIn("LAUNCHER_PASS", output, output[-3000:])
        self.assertNotIn("LAUNCHER_FAIL", output)
        self.assertTrue(action_launched, output[-3000:])


if __name__ == "__main__":
    unittest.main()
