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
assert.equal(findActions("audio")[0].action, "audio");
assert.equal(findActions("mic-mute")[0].action, "mic-mute");
assert.equal(findActions("vol 37")[0].action, "volume-set");
assert.equal(findActions("vol 37")[0].argument, 37);
assert.equal(findActions("backlight 60")[0].action, "brightness-set");
assert.equal(findActions("backlight 60")[0].argument, 60);
assert.equal(findActions("mic mute")[0].action, "mic-mute");
for (const input of ["vol " + "9".repeat(400), "vol 37 extra", "backlight 60 extra"]) {
    const row = findActions(input)[0];
    assert.equal(row.disabled, true, input);
    assert.equal(row.action, undefined, input);
    assert.equal(row.argument, undefined, input);
}
assert.deepEqual(findActions("shutdown"), []);
for (const input of ["dnd on", "DND ON", "Do Not Disturb ON"])
    assert.equal(findActions(input, {dnd: "Off"})[0].action, "dnd-on", input);
for (const input of ["dnd off", "DND OFF", "Do Not Disturb OFF"])
    assert.equal(findActions(input, {dnd: "On"})[0].action, "dnd-off", input);
assert.equal(findActions("dnd on", {dnd: "Off"})[0].action,
    findActions("dnd on", {dnd: "On"})[0].action, "DND on intent stays idempotent");
const dndOn = findActions("dnd on", {dnd: "Off"})[0];
const dndOff = findActions("dnd off", {dnd: "On"})[0];
assert.equal(dndOn.name, "Turn Do Not Disturb on");
assert.equal(dndOff.name, "Turn Do Not Disturb off");
assert.match(dndOn.comment, /Off/i);
assert.match(dndOff.comment, /On/i);

const volumeSet = findActions("ÂM LƯỢNG 42.5", {volume: "43%"})[0];
assert.equal(volumeSet.action, "volume-set");
assert.equal(volumeSet.argument, 42.5);
assert.equal(volumeSet.name, "Set volume to 42.5%");
assert.match(volumeSet.comment, /43%/);
const brightnessSet = findActions("ĐỘ SÁNG 63", {brightness: "60%"})[0];
assert.equal(brightnessSet.action, "brightness-set");
assert.equal(brightnessSet.argument, 63);
assert.equal(brightnessSet.name, "Set brightness to 63%");
assert.match(brightnessSet.comment, /60%/);

const actionIds = new Set(findActions("").map(item => item.action));
for (const id of ["home", "config", "notifications", "system", "power", "clipboard",
    "screenshot", "windows", "wallpaper"])
    assert.ok(actionIds.has(id), "missing navigation action: " + id);
const unavailable = findActions("system", {}, {system: false})[0];
assert.equal(unavailable.action, "system");
assert.equal(unavailable.disabled, true);
"""], check=True)
