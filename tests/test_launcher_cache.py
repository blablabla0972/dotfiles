"""Check the real QML launcher cache and preserve search/category results."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("qs") and os.environ.get("WAYLAND_DISPLAY"),
                     "requires Quickshell and a live Wayland session")
class LauncherCacheTests(unittest.TestCase):
    def test_cache_and_search_results(self):
        launcher = (Path(__file__).resolve().parents[1]
                    / "config/quickshell/rice-shell/launcher").as_uri()
        source = '''
import QtQuick
import Quickshell
import "LAUNCHER_URI"
ShellRoot {
    Launcher { id: launcher; targetScreen: Quickshell.screens[0] }
    Timer {
        interval: 150; running: true
        onTriggered: {
            var errors = [];
            var first = launcher.getZeroStateApps();
            if (first !== launcher.getZeroStateApps()) errors.push("zero-state cache miss");
            launcher.searchText = "rnote";
            launcher.searchText = "";
            if (first !== launcher.getZeroStateApps()) errors.push("typing invalidated zero state");
            var queries = ["", "r", "RNOTE", "note", "settings", "  file  ", "unmatched-xyz"];
            for (var c = 0; c < launcher.categories.length; c++) {
                launcher.selectedCategory = launcher.categories[c];
                for (var q = 0; q < queries.length; q++) {
                    var query = queries[q].trim().toLowerCase();
                    var expected = [];
                    for (var i = 0; i < launcher.allApps.length; i++) {
                        var app = launcher.allApps[i];
                        if (!app || !app.name || app.noDisplay
                            || !launcher.matchesCategory(app, launcher.selectedCategory)) continue;
                        var name = app.name.toLowerCase();
                        var rank = name.startsWith(query) ? 0 : name.includes(query) ? 1 : 2;
                        var matches = rank < 2 || (app.genericName || "").toLowerCase().includes(query)
                            || (app.comment || "").toLowerCase().includes(query);
                        for (var k = 0; !matches && app.keywords && k < app.keywords.length; k++)
                            matches = (app.keywords[k] || "").toLowerCase().includes(query);
                        if (matches) expected.push({app: app, rank: rank, order: i});
                    }
                    expected.sort(function(a, b) {
                        return query ? a.rank - b.rank || a.order - b.order
                                     : a.app.name.localeCompare(b.app.name);
                    });
                    if (query) expected = expected.slice(0, 40);
                    launcher.searchText = queries[q];
                    var expectedIds = expected.map(function(record) { return record.app.id; });
                    var actualIds = launcher.filteredApps.map(function(app) { return app.id; });
                    if (JSON.stringify(expectedIds) !== JSON.stringify(actualIds))
                        errors.push(launcher.selectedCategory + ":" + queries[q]);
                }
            }
            launcher.searchText = "> echo test";
            if (launcher.filteredApps.length !== 1 || !launcher.filteredApps[0].isCommand
                || launcher.filteredApps[0].command !== "echo test") errors.push("command mode");
            console.log(errors.length ? "LAUNCHER_FAIL " + errors.join("; ") : "LAUNCHER_PASS");
            Qt.quit();
        }
    }
}
'''.replace("LAUNCHER_URI", launcher)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "check.qml"
            path.write_text(source)
            result = subprocess.run(["qs", "--no-color", "-p", str(path)],
                                    capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output[-3000:])
        self.assertIn("LAUNCHER_PASS", output, output[-3000:])
        self.assertNotIn("LAUNCHER_FAIL", output)


if __name__ == "__main__":
    unittest.main()
