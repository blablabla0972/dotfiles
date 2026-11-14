"""Focused behavior tests for the Bluetooth drawer's production QML helpers.

The test executes the selected JavaScript functions from the QML component in
Node with fake adapter/device objects. It never imports Bluetooth or touches
BlueZ, and it requires no additional repository test harness files.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QML_PATH = ROOT / "config/quickshell/rice-shell/dashboard/BluetoothDrawer.qml"


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunction\s+{re.escape(name)}\s*\(", source)
    if match is None:
        raise AssertionError(f"production QML function {name}() is missing")

    opening_paren = source.find("(", match.start())
    closing_paren = source.find(")", opening_paren)
    opening_brace = source.find("{", closing_paren)
    if min(opening_paren, closing_paren, opening_brace) < 0:
        raise AssertionError(f"could not read production QML function {name}()")

    depth = 0
    quote = None
    escaped = False
    regex_literal = False
    regex_class = False
    regex_escaped = False
    line_comment = False
    block_comment = False
    index = opening_brace
    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            line_comment = char != "\n"
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif regex_literal:
            if regex_escaped:
                regex_escaped = False
            elif char == "\\":
                regex_escaped = True
            elif char == "[":
                regex_class = True
            elif char == "]":
                regex_class = False
            elif char == "/" and not regex_class:
                regex_literal = False
        elif char in "'\"`":
            quote = char
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char == "/" and (
            source[index - 1] in "([{=:;,!&|?+-*%^~<>"
            or re.search(r"\b(?:return|case|throw|yield|await)\s*$", source[opening_brace:index])
        ):
            regex_literal = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                header = source[match.start() : opening_brace]
                header = re.sub(r"\)\s*:\s*[A-Za-z_][A-Za-z_0-9]*\s*$", ")", header)
                return header + source[opening_brace : index + 1]
        index += 1

    raise AssertionError(f"unterminated production QML function {name}()")


class BluetoothDrawerRedesignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("node") is None:
            raise unittest.SkipTest("Node.js is required to execute the production QML helpers")
        cls.qml_source = QML_PATH.read_text(encoding="utf-8")

    def run_qml(self, function_names: tuple[str, ...], assertions: str) -> None:
        functions = "\n".join(extract_function(self.qml_source, name) for name in function_names)
        bindings = ", ".join(f"{name}: {name}" for name in function_names)
        script = f"""
const assert = require('node:assert/strict');
const root = {{}};
const scanStopTimer = {{ restartCount: 0, stopCount: 0,
  restart() {{ this.restartCount++; }}, stop() {{ this.stopCount++; }} }};
const powerTimeout = {{ restartCount: 0, stopCount: 0,
  restart() {{ this.restartCount++; }}, stop() {{ this.stopCount++; }} }};
const actionTimeout = {{ restartCount: 0, stopCount: 0,
  restart() {{ this.restartCount++; }}, stop() {{ this.stopCount++; }} }};
const forgetTimeout = {{ restartCount: 0, stopCount: 0,
  restart() {{ this.restartCount++; }}, stop() {{ this.stopCount++; }} }};
const agentProcess = {{ running: false, writes: [], write(value) {{ this.writes.push(value); }} }};
{functions}
Object.assign(root, {{ {bindings} }});
{assertions}
"""
        result = subprocess.run(
            ["node", "-e", script], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_component_loads_with_a_fake_adapter(self) -> None:
        quickshell = shutil.which("quickshell")
        if quickshell is None:
            self.skipTest("Quickshell is not installed")
        directory = (ROOT / "config/quickshell/rice-shell/dashboard").as_uri().replace("file://", "file:")
        harness = f'''import QtQuick
import Quickshell
import "{directory}" as Dashboard

Scope {{
    QtObject {{
        id: fakeAdapter
        property bool enabled: true
        property bool discovering: true
        property string name: "Fixture adapter"
        property var devices: ({{ values: [] }})
        property int state: 0
    }}

    Item {{
        width: 360
        height: 520
        visible: false
        Dashboard.BluetoothDrawer {{
            anchors.fill: parent
            visible: false
            adapterOverride: fakeAdapter
        }}
    }}
}}
'''
        with tempfile.TemporaryDirectory(prefix="bluetooth-drawer-qml-") as temp_dir:
            qml_path = Path(temp_dir) / "main.qml"
            qml_path.write_text(harness, encoding="utf-8")
            try:
                result = subprocess.run(
                    [quickshell, "--path", str(qml_path)],
                    capture_output=True,
                    text=True,
                    timeout=4,
                    check=False,
                )
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
            except subprocess.TimeoutExpired as error:
                output = "".join(
                    value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                    for value in (error.stdout, error.stderr)
                )
            diagnostics = [
                line for line in output.splitlines()
                if "WARN scene:" in line or "ERROR scene:" in line or "FATAL" in line
            ]
            self.assertEqual(diagnostics, [], output)

    def test_native_devices_are_projected_into_three_sections(self) -> None:
        self.run_qml(
            ("visibleDevices", "classifyDevices"),
            """
const adapter = {};
root.btAdapter = adapter;
const connected = { address: 'AA:00:00:00:00:01', name: 'Headphones', connected: true,
  paired: true, batteryAvailable: true, battery: 0.82, adapter };
const paired = { address: 'AA:00:00:00:00:02', name: 'Keyboard', connected: false,
  paired: true, batteryAvailable: false, adapter };
const available = { address: 'AA:00:00:00:00:03', name: 'Speaker', connected: false,
  paired: false, batteryAvailable: false, adapter };
const devices = visibleDevices([connected, paired, available]);
const sections = classifyDevices(devices);
assert.deepEqual(sections.connected.map(d => d.name), ['Headphones']);
assert.deepEqual(sections.paired.map(d => d.name), ['Keyboard']);
assert.deepEqual(sections.available.map(d => d.name), ['Speaker']);
assert.equal(sections.connected[0].batteryPercent, 82);
assert.equal(sections.paired[0].batteryPercent, null);
assert.equal(sections.connected[0].deviceRef, connected);
assert.equal(sections.connected[0].adapterRef, adapter);
""",
        )

    def test_pairing_events_require_the_active_device_context(self) -> None:
        self.run_qml(
            ("isValidMac", "macFromContextLine", "isEventForActiveDevice"),
            """
root.activeDeviceMac = 'AA:00:00:00:00:01';
const targetOutput = '[CHG] Device AA:00:00:00:00:01 Name: Headphones\\n[agent] Confirm passkey 123456';
const targetMatch = { index: targetOutput.indexOf('Confirm passkey'), 0: 'Confirm passkey' };
assert.equal(isEventForActiveDevice(targetMatch, targetOutput), true);
const otherOutput = '[CHG] Device AA:00:00:00:00:02 Connected: yes';
const otherMatch = { index: otherOutput.indexOf('Connected: yes'), 0: 'Connected: yes' };
assert.equal(isEventForActiveDevice(otherMatch, otherOutput), false);
const unscopedOutput = '[agent] Confirm passkey 123456';
const unscopedMatch = { index: unscopedOutput.indexOf('Confirm passkey'), 0: 'Confirm passkey' };
assert.equal(isEventForActiveDevice(unscopedMatch, unscopedOutput), false);
""",
        )

    def test_pairing_prompt_waits_for_user_and_never_auto_trusts(self) -> None:
        self.run_qml(
            ("isValidMac", "macFromContextLine", "isEventForActiveDevice",
             "freshMatch", "finishDeviceAction", "handleAgentOutput"),
            """
root.isConnecting = true;
root.actionStage = 'pair';
root.activeDeviceMac = 'AA:00:00:00:00:01';
root.activeDeviceName = 'Headphones';
root.agentOutputOffset = 0;
root.agentOutputTail = '';
handleAgentOutput('[CHG] Device AA:00:00:00:00:01 Name: Headphones\\n[agent] Confirm passkey 123456\\n');
assert.equal(root.pairingPromptType, 'confirm');
assert.match(root.pairingPromptText, /123456/);
assert.deepEqual(agentProcess.writes, []);
root.isConnecting = true;
root.actionStage = 'pair';
root.activeDeviceMac = 'AA:00:00:00:00:01';
root.activeDeviceName = 'Headphones';
root.agentOutputOffset = 0;
root.agentOutputTail = '';
handleAgentOutput('[CHG] Device AA:00:00:00:00:01 Paired: yes\\n');
assert.equal(root.actionMessage, 'Paired with Headphones');
assert.deepEqual(agentProcess.writes, []);
""",
        )

    def test_pairing_input_is_protocol_bounded_and_line_safe(self) -> None:
        self.run_qml(
            ("validatePairingInput",),
            """
assert.equal(validatePairingInput('passkey', '123456'), true);
assert.equal(validatePairingInput('passkey', '1234567'), false);
assert.equal(validatePairingInput('passkey', '12\\n3'), false);
assert.equal(validatePairingInput('pin', 'ab12-!'), true);
assert.equal(validatePairingInput('pin', '12345678901234567'), false);
assert.equal(validatePairingInput('pin', 'x\\rpair AA:00:00:00:00:02'), false);
""",
        )

    def test_scan_cleanup_only_stops_a_scan_owned_by_this_page(self) -> None:
        self.run_qml(
            ("startScan", "stopScan"),
            """
const adapter = { enabled: true, discovering: true };
root.btAdapter = adapter;
root.isPowered = true;
root.scanOwnedAdapter = null;
root.statusMessage = '';
startScan();
stopScan();
assert.equal(adapter.discovering, true);
assert.equal(root.scanOwnedAdapter, null);
adapter.discovering = false;
startScan();
assert.equal(root.scanOwnedAdapter, adapter);
assert.equal(adapter.discovering, true);
stopScan();
assert.equal(adapter.discovering, false);
assert.equal(root.scanOwnedAdapter, null);
""",
        )

    def test_adapter_power_requests_are_explicit_and_pending_aware(self) -> None:
        self.run_qml(
            ("startScan", "stopScan", "requestAdapterPower", "observeAdapterPower"),
            """
let powered = true;
const requests = [];
const adapter = { discovering: false };
Object.defineProperty(adapter, 'enabled', {
  get() { return powered; }, set(value) { requests.push(value); }
});
root.btAdapter = adapter;
root.isPowerPending = false;
root.pendingPowerTarget = null;
root.isConnecting = false;
root.statusMessage = '';
root.scanOwnedAdapter = null;
assert.equal(requestAdapterPower(false), true);
assert.equal(root.isPowerPending, true);
assert.equal(requestAdapterPower(true), false);
assert.deepEqual(requests, [false]);
powered = false;
observeAdapterPower();
assert.equal(root.isPowerPending, false);
assert.equal(root.pendingPowerTarget, null);
""",
        )

    def test_forget_runs_only_after_confirmation(self) -> None:
        self.run_qml(
            ("isValidMac", "isValidDeviceEntry", "requestForget", "cancelForget",
             "finishForget", "observeForget", "confirmForget"),
            """
const adapter = {};
let forgetCount = 0;
const device = { address: 'AA:00:00:00:00:01', paired: true, adapter,
  forget() { forgetCount++; } };
root.btAdapter = adapter;
root.pendingForgetDevice = null;
root.forgetDialogOpen = false;
root.isForgetPending = false;
root.statusMessage = '';
requestForget({ deviceRef: device, adapterRef: adapter, mac: device.address, paired: true });
assert.equal(root.forgetDialogOpen, true);
assert.equal(forgetCount, 0);
confirmForget();
assert.equal(forgetCount, 1);
assert.equal(root.forgetDialogOpen, false);
assert.equal(root.isForgetPending, true);
""",
        )


if __name__ == "__main__":
    unittest.main()
