from pathlib import Path
import subprocess
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/launcher"


class LauncherQuickActionsTests(unittest.TestCase):
    def test_parser_and_action_allowlist(self):
        script = (LAUNCHER / "QuickActions.js").read_text().removeprefix(".pragma library\n")
        subprocess.run(["node", "-e", script + r"""
const assert = require("node:assert/strict");
for (const [input, expected] of [
    ["1+2*3", "7"], [" (1 + 2) * -3 ", "-9"], ["8/4/2", "1"],
    ["2--3", "5"], ["+.5-1.", "-0.5"], ["-0", "0"], ["0.1+0.2", "0.3"]
]) assert.deepEqual(calculate(input), {value: expected});
for (const input of ["", "1/0", "0/(-0)", "1/(2-2)", "NaN", "Infinity", "1e309",
    "1+","()", "(1", "1)", "2(3)", "1 2", "1..2", "1; touch /tmp/qa",
    "Qt.quit()", "0x10", "9".repeat(200) + "*" + "9".repeat(200), "-".repeat(513)])
    assert.ok(calculate(input).error, input);
assert.match(calculate("1/0").error, /zero/i);
assert.deepEqual(findActions("volume down").map(item => item.action), ["volume-down"]);
assert.deepEqual(findActions("DND").map(item => item.action), ["dnd"]);
assert.deepEqual(findActions("shutdown"), []);
assert.deepEqual(findActions("").map(item => item.action).sort(),
    ["brightness-down", "brightness-up", "dnd", "power", "reload", "system",
     "volume-down", "volume-up"]);
"""], check=True)
