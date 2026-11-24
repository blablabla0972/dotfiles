import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "config/quickshell/rice-shell/overlays/WindowSwitcherState.js"
BINDS = ROOT / "config/hypr/config/binds.lua"


@unittest.skipUnless(shutil.which("node"), "node required")
class WindowSwitcherStateTest(unittest.TestCase):
    def test_order_and_selection_follow_live_addresses(self):
        check = r"""
const assert = require('node:assert/strict');
const ws = (address, id, title = '') => ({address, title, workspace: {id}});
const a = ws('abc', 2, '\u{1f680}'.repeat(4096));
const b = ws('0xdef', 1);
const c = ws('123', 2);
const input = [c, null, ws('', 1), a, b, ws('invalid', 1), {address: '444'}];
assert.deepEqual(orderedWindows(input, 'abc').map(w => w.address), ['abc', '0xdef', '123']);
assert.equal(orderedWindows(input, 'abc')[0].title, a.title);
const local = {address: 'aaa', workspace: {name: 'work'}};
const peer = {address: 'bbb', workspace: {name: 'work'}};
const remote = {address: '111', workspace: {name: 'other'}};
assert.deepEqual(orderedWindows([remote, peer, local], 'aaa', 'work'), [local, peer, remote]);
assert.deepEqual(orderedWindows([remote, peer], '', 'work'), [peer, remote]);
assert.equal(stepAddress([], '', 1), '');
assert.equal(stepAddress([a], '', -1), 'abc');
assert.equal(stepAddress([a, b, c], 'abc', 1), '0xdef');
assert.equal(stepAddress([a, b, c], 'abc', -1), '123');
assert.equal(stepAddress([a, b, c], '123', 1), 'abc');
assert.equal(stepAddress([a, b, c], 'abc', 2), '123');
assert.equal(stepAddress([a, b, c], 'abc', -2), '0xdef');
assert.equal(stepAddress([a, b, c], '0xdef', -4), 'abc');
assert.equal(stepAddress([b, c], 'abc', -1), '123');
assert.deepEqual(activationCommands([a, b], 'abc', false), ['focuswindow address:0xabc']);
assert.deepEqual(activationCommands([a, b], '0xdef', false), ['focuswindow address:0xdef']);
assert.deepEqual(activationCommands([a, b], 'abc', true), [
    'hl.dsp.focus({window="address:0xabc"})',
    'hl.dsp.window.fullscreen({window="address:0xabc",mode=1,action="set"})',
]);
assert.deepEqual(activationCommands([b], 'abc', true), []);
"""
        subprocess.run(["node", "-e", STATE.read_text() + check], check=True)


@unittest.skipUnless(shutil.which("lua"), "lua required")
class WindowSwitcherKeybindTest(unittest.TestCase):
    def test_real_lua_binds_native_only(self):
        check = r"""
local binds = {}
local actions = {}
local dispatchers = setmetatable({}, {__call = function() end, __index = function(_, name)
    return function() return name end
end})
hl = {
    bind = function(key, action, flags) binds[key] = {action, flags} end,
    dispatch = function(action) table.insert(actions, action) end,
    config = function() end,
    dsp = setmetatable({
        exec_cmd = function(command) return command end,
        global = function(name) return name end,
    }, {
        __index = function() return dispatchers end,
    }),
}
TERMINAL, FILE_MANAGER, CALCULATOR, BROWSER = 'terminal', 'files', 'calc', 'browser'
NUM_WPM, MONITOR1 = 5, 'test'
dofile(arg[1])
binds['SUPER + Tab'][1]()
binds['SUPER + SHIFT + Tab'][1]()
assert(actions[1] == 'rice:window-switcher-next')
assert(actions[2] == 'rice:window-switcher-prev' and #actions == 2)
assert(binds['code:133'][1] == 'rice:window-switcher-super-left')
assert(binds['code:134'][1] == 'rice:window-switcher-super-right')
assert(binds['code:133'][2].non_consuming and binds['code:134'][2].non_consuming)
assert(binds['ALT + Tab'][1] == 'cycle_next')
assert(binds['SUPER + Escape'][1] == 'test "$(qs ipc -p ~/.config/quickshell/rice-shell call rice cancelWindowSwitcher 2>/dev/null)" = true || hyprctl kill')
"""
        subprocess.run(["lua", "-", str(BINDS)], input=check, text=True, check=True)
