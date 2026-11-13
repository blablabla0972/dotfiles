"""Check tray-button dispatch without touching the running Wayland shell."""

import subprocess
import unittest
from pathlib import Path


TRAY = Path(__file__).resolve().parents[1] / "config/quickshell/rice-shell/bar/StatusTray.qml"


class BarTrayPointerDispatchTest(unittest.TestCase):
    def test_button_actions(self):
        js = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
assert.match(source, /acceptedButtons:\s*Qt\.LeftButton\s*\|\s*Qt\.MiddleButton\s*\|\s*Qt\.RightButton/);
const marker = 'onTapped: (eventPoint, button) => {';
const start = source.indexOf(marker);
assert.ok(start !== -1, 'tray TapHandler missing');
const open = source.indexOf('{', start);
let depth = 0;
let close = -1;
for (let i = open; i < source.length; i++) {
    if (source[i] === '{') {
        depth++;
    } else if (source[i] === '}') {
        depth--;
        if (depth === 0) {
            close = i;
            break;
        }
    }
}
assert.ok(close > open, 'tray handler must have a closing brace');
const calls = [];
const item = {
    hasMenu: true,
    menu: 'mock-menu',
    activate: () => calls.push('primary'),
    secondaryActivate: () => calls.push('secondary'),
};
const context = {
    Qt: { LeftButton: 1, RightButton: 2, MiddleButton: 4 },
    trayItemDelegate: { modelData: item },
    trayContextMenu: { openMenu: (menu, x, y) => calls.push(['menu', menu, x, y]) },
    Math,
};
const tapped = vm.runInNewContext(`(eventPoint, button) => ${source.slice(open, close + 1)}`, context);
const point = { scenePosition: { x: 30.6, y: 7.2 } };
function check(button, expected) {
    calls.length = 0;
    tapped(point, button);
    assert.equal(JSON.stringify(calls), JSON.stringify(expected));
}
check(context.Qt.LeftButton, ['primary']);
check(context.Qt.MiddleButton, ['secondary']);
check(context.Qt.RightButton, [['menu', 'mock-menu', 31, 7]]);
item.hasMenu = false;
check(context.Qt.RightButton, []);
"""
        result = subprocess.run(
            ["node", "-e", js, str(TRAY)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
