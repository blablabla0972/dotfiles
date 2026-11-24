from pathlib import Path
import subprocess
import unittest

SETTINGS = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/settings"


class SettingsSearchTests(unittest.TestCase):
    def test_search_and_routes(self):
        script = (SETTINGS / "Registry.js").read_text()
        subprocess.run(["node", "-e", "const qsTr = s => s;\n" + script + r"""
const assert = require("node:assert/strict");
const top = (q, route) => assert.equal(search(q)[0]?.route, route, q);
top("dark", "appearance#color-mode");
top("calculator history", "launcher#launcher-calculations");
top("clock seconds", "shell#shell-showClockSeconds");
top("do sang", "display#brightness");
top("ĐỘ SÁNG", "display#brightness");
top("wallpapre", "appearance#wallpaper");
top("volume output", "sound#output-volume");
assert(search("top bar clock").some(x => x.route === "shell#shell-showClockSeconds"));
assert(search("wifi").some(x => x.route === "network#wifi" || x.route === "network"));
assert.equal(search("zzzzzzzz").length, 0);
assert.equal(search(" ").length, 0);
assert(validRoute("devices#brightness"));
assert(!validRoute("shell#unknown-setting"));
for (const page of pages) {
    assert(validRoute(page.id));
    for (const row of rowsFor(page)) assert(validRoute(page.id + "#" + row[0]));
}
assert.equal(new Set(search("volume").map(x => x.route)).size, search("volume").length);
"""], check=True)


if __name__ == "__main__":
    unittest.main()
