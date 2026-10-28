"""Offline carousel contracts: execute the QML JS and the real wrapper."""
import json
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
CAROUSEL = ROOT / "config/quickshell/wallpaper-switcher"


@unittest.skipUnless(shutil.which("node"), "node is required to execute the QML state machine")
class ApplyStateTests(unittest.TestCase):
    def js(self, scenario):
        script = r"""
const fs = require('node:fs'), vm = require('node:vm');
const assert = require('node:assert/strict');
const api = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), api);
let s = api.create('test-session');
const send = (type, fields = {}) => s = api.reduce(s, {type, ...fields});
const request = wallpaper => send('request', {wallpaper});
const ack = (active, status = 'applied', fields = {}) => JSON.stringify({
    schema_version: 1, request_id: active.requestId, wallpaper: active.wallpaper,
    status, palette_revision: status === 'applied' ? 'a'.repeat(64) : null,
    error_code: status === 'applied' ? null : 'matugen_failed', ...fields
});
const finish = (active, status = 'applied', fields = {}, code = status === 'applied' ? 0 : 1) => {
    send('stdout', {requestId: active.requestId, text: ack(active, status, fields)});
    send('exit', {requestId: active.requestId, code, exitStatus: 0});
};
""" + scenario
        result = subprocess.run(
            ["node", "-e", script, str(CAROUSEL / "ApplyState.js")],
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_navigation_and_three_competing_intentions(self):
        self.js(r"""
request('/A.png'); const first = s.active;
for (let i = 0; i < 50; i++) send('select', {wallpaper: `/ảnh ${i}.png`});
assert.equal(s.selection, '/ảnh 49.png');
assert.equal(s.active.requestId, first.requestId);
request('/B.png'); request('/C.png');
assert.equal(s.queued, '/C.png'); assert.equal(s.applied, '');
finish(first);
assert.equal(s.applied, '/A.png'); assert.equal(s.active.wallpaper, '/C.png');
assert.equal(s.phase, 'pending'); assert.notEqual(s.active.requestId, first.requestId);
const latest = s.active, before = JSON.stringify(s);
finish(first); assert.equal(JSON.stringify(s), before);
finish(latest); assert.equal(s.applied, '/C.png');
assert.equal(s.phase, 'applied'); assert.equal(s.active, null);
assert.equal(s.selection, '/ảnh 49.png');
""")

    def test_duplicate_apply_and_latest_intention_returning_to_active(self):
        self.js(r"""
request('/A'); const first = s.active;
request('/A'); assert.equal(s.queued, '');
request('/B'); request('/A'); assert.equal(s.queued, '');
finish(first); const done = JSON.stringify(s);
finish(first); assert.equal(JSON.stringify(s), done);
request('/A'); assert.ok(s.active);
assert.notEqual(s.active.requestId, first.requestId);
""")

    def test_stdout_and_exit_may_arrive_in_either_order(self):
        self.js(r"""
for (const reverse of [false, true]) {
    s = api.create('order-' + reverse); request('/ảnh có dấu.png'); const a = s.active;
    const events = [
        {type: 'stdout', requestId: a.requestId, text: ack(a)},
        {type: 'exit', requestId: a.requestId, code: 0, exitStatus: 0}
    ];
    if (reverse) events.reverse();
    s = api.reduce(s, events[0]); assert.equal(s.applied, '');
    s = api.reduce(s, events[1]); assert.equal(s.applied, a.wallpaper);
}
""")

    def test_invalid_or_mismatched_ack_never_commits(self):
        self.js(r"""
for (const patch of [
    {schema_version: 2}, {schema_version: '1'}, {request_id: 'stale'},
    {wallpaper: '/other'}, {status: 'success'}, {palette_revision: null},
    {palette_revision: 'sha256:bad'}, {error_code: 'contradiction'}
]) {
    s = api.create('validation'); request('/A'); finish(s.active, 'applied', patch);
    assert.equal(s.applied, ''); assert.equal(s.phase, 'unknown');
}
for (const raw of ['', 'not json', '[]', '{}', 'null', ack({requestId: 'x', wallpaper: '/A'}) + '\n{}']) {
    s = api.create('malformed'); request('/A'); const a = s.active;
    send('stdout', {requestId: a.requestId, text: raw});
    send('exit', {requestId: a.requestId, code: 0, exitStatus: 0});
    assert.equal(s.applied, ''); assert.equal(s.phase, 'unknown');
}
""")

    def test_exit_must_agree_with_ack(self):
        self.js(r"""
for (const [code, exitStatus] of [[1, 0], [0, 1], [127, 0]]) {
    s = api.create('exit'); request('/A'); const a = s.active;
    send('stdout', {requestId: a.requestId, text: ack(a)});
    send('exit', {requestId: a.requestId, code, exitStatus});
    assert.equal(s.phase, 'unknown'); assert.equal(s.applied, '');
}
""")

    def test_failures_preserve_confirmed_wallpaper_and_revision(self):
        self.js(r"""
request('/original'); finish(s.active);
for (const [status, error] of [['failed', 'matugen_failed'], ['rolled_back', 'noctalia_template_failed'], ['failed', 'invalid_wallpaper']]) {
    request('/candidate'); finish(s.active, status, {error_code: error});
    assert.equal(s.applied, '/original'); assert.equal(s.revision, 'a'.repeat(64));
    assert.equal(s.phase, status); assert.equal(s.error, error);
}
""")

    def test_timeout_and_escape_keep_transaction_and_queue_alive(self):
        self.js(r"""
request('/A'); const a = s.active; request('/B');
send('timeout', {requestId: a.requestId});
assert.equal(s.phase, 'unknown'); assert.equal(s.active.requestId, a.requestId);
assert.equal(s.applied, ''); assert.equal(s.queued, '/B');
send('close'); assert.equal(s.closed, true); assert.ok(s.active);
finish(a); assert.equal(s.active.wallpaper, '/B');
finish(s.active); assert.equal(s.applied, '/B'); assert.equal(s.active, null);
""")

    def test_failed_launch_and_stale_transport_events(self):
        self.js(r"""
request('/A'); const a = s.active, before = JSON.stringify(s);
for (const type of ['stdout', 'exit', 'timeout', 'launch_failed']) {
    send(type, {requestId: 'old', text: ack(a), code: 0, exitStatus: 0});
    assert.equal(JSON.stringify(s), before);
}
send('launch_failed', {requestId: a.requestId});
assert.equal(s.phase, 'failed'); assert.equal(s.error, 'process_start_failed');
assert.equal(s.applied, ''); assert.equal(s.active, null);
""")

    def test_exit_then_timeout_keeps_waiting_for_delayed_stdout(self):
        self.js(r"""
request('/A'); const a = s.active;
send('exit', {requestId: a.requestId, code: 0, exitStatus: 0});
send('timeout', {requestId: a.requestId});
assert.ok(s.active); assert.equal(s.phase, 'unknown'); assert.equal(s.applied, '');
send('stdout', {requestId: a.requestId, text: ack(a)});
assert.equal(s.phase, 'applied'); assert.equal(s.applied, '/A');
""")

    def test_adaptive_palette_validation_and_native_fallback(self):
        self.js(r"""
const colors = Object.fromEntries(['background', 'surface_low', 'surface', 'surface_high',
    'text_primary', 'text_secondary', 'accent', 'on_accent', 'outline', 'focus_ring', 'danger']
    .map((role, i) => [role, '#' + (0x101010 + i).toString(16)]));
const token = {schema_version: 1, mode: 'dark', colors,
    materials: {panel: {opacity: 0.96}},
    source_palette_sha256: 'b'.repeat(64), wallpaper_sha256: 'c'.repeat(64)};
const read = value => api.adaptivePalette(JSON.stringify(value), 'dark', 'b'.repeat(64));
assert.equal(read(token).mPrimary, colors.accent);
assert.equal(read(token).mOnSurface, colors.text_primary);
assert.equal(read(token).panelOpacity, 0.96);
assert.equal(api.adaptivePalette(JSON.stringify(token), 'dark', 'd'.repeat(64)), null);
assert.equal(api.adaptivePalette(JSON.stringify(token), 'dark', null), null);
for (const patch of [{schema_version: 2}, {mode: 'light'}, {mode: 'auto'},
    {source_palette_sha256: 'bad'}, {colors: {...colors, danger: 'red'}},
    {colors: {...colors, focus_ring: undefined}}, {materials: {}},
    ...[-0.1, 1.1, '0.96', null].map(opacity => ({materials: {panel: {opacity}}}))])
    assert.equal(read({...token, ...patch}), null);
assert.equal(api.adaptivePalette('{bad', 'dark'), null);
assert.equal(api.adaptivePalette('', 'dark'), null);
""")

    def test_palette_revision_accepts_real_digest_only_for_current_generation(self):
        self.js(r"""
const crypto = require('node:crypto');
const digest = crypto.createHash('sha256').update('native palette bytes\n').digest('hex');
const output = digest + '  /config space/matugen.json\0';
assert.equal(api.paletteRevision(4, 4, output, 0, 0), digest);
assert.equal(api.paletteRevision(5, 4, output, 0, 0), null);
for (const [text, code, status] of [[output, 1, 0], [output, 0, 1], ['bad', 0, 0]])
    assert.equal(api.paletteRevision(4, 4, text, code, status), null);
""")

    def test_hash_process_waits_for_old_stdout_before_reusing_generation(self):
        qml = (CAROUSEL / 'shell.qml').read_text()
        pump = re.search(r'    function pumpPaletteHash\(\) \{.*?\n    \}', qml, re.S).group()
        self.js(pump + r"""
let paletteHashWanted = true, paletteGeneration = 2;
const paletteFile = {path: '/native palette Ảnh.json'};
const paletteHash = {running: false, generation: 1, outputReady: false, resultCode: 0};
pumpPaletteHash();
assert.equal(paletteHash.generation, 1, 'exit alone must not reuse the collector');
paletteHash.outputReady = true;
pumpPaletteHash();
assert.equal(paletteHash.generation, 2); assert.equal(paletteHash.running, true);
assert.deepEqual(paletteHash.command, ['sha256sum', '--zero', '--', paletteFile.path]);
""")

    def test_preview_latest_selection_and_mode_reject_late_or_failed_results(self):
        self.js(r"""
let preview = api.createPreview('preview');
preview = api.selectPreview(preview, '/Ảnh first.png', 'dark'); const first = preview;
for (let i = 0; i < 50; i++) preview = api.selectPreview(preview, `/Ảnh ${i}.png`, 'dark');
const envelope = p => JSON.stringify({schema_version: 1, request_id: p.requestId,
    wallpaper: p.wallpaper, mode: p.mode,
    swatches: ['#123456', '#234567', '#345678', '#456789', '#567890']});
const before = JSON.stringify(preview);
preview = api.finishPreview(preview, first.requestId, envelope(first), 0, 0);
assert.equal(JSON.stringify(preview), before);
preview = api.finishPreview(preview, preview.requestId, envelope(preview), 0, 0);
assert.equal(preview.phase, 'ready'); assert.equal(preview.swatches.length, 5);
const dark = preview;
preview = api.selectPreview(preview, preview.wallpaper, 'light');
assert.equal(preview.swatches.length, 0);
preview = api.finishPreview(preview, dark.requestId, envelope(dark), 0, 0);
assert.equal(preview.phase, 'pending');
for (const raw of ['bad json', envelope(dark), envelope(preview).replace('#123456', 'red')]) {
    const failed = api.finishPreview(preview, preview.requestId, raw, 0, 0);
    assert.equal(failed.phase, 'failed'); assert.equal(failed.swatches.length, 0);
}
const failed = api.finishPreview(preview, preview.requestId, envelope(preview), 1, 0);
assert.equal(failed.phase, 'failed'); assert.equal(failed.swatches.length, 0);
""")


class PreviewHelperTests(unittest.TestCase):
    def run_preview(self, output=None, status=0, real=False):
        with tempfile.TemporaryDirectory(prefix='carousel-preview-') as temp:
            base = Path(temp)
            wallpaper = base / 'Ảnh spaces ; $(touch injected).ppm'
            wallpaper.write_bytes(b'P6\n4 4\n255\n' + bytes([69, 103, 137]) * 16)
            roles = ['primary', 'secondary', 'tertiary', 'surface', 'on_surface']
            if output is None:
                output = json.dumps({'colors': {role: {mode: {'color': '#123456'}
                                    for mode in ['dark', 'light']} for role in roles}})
            record = base / 'record.json'
            if not real:
                stub = base / 'matugen'
                stub.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
config = pathlib.Path(args[args.index('--config') + 1])
pathlib.Path(os.environ['PREVIEW_RECORD']).write_text(json.dumps({
    'args': args, 'config_path': str(config), 'config': config.read_text(),
    'xdg': {key: os.environ[key] for key in ['XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME']}}))
print(os.environ['PREVIEW_OUTPUT'])
sys.exit(int(os.environ['PREVIEW_STATUS']))
''')
                stub.chmod(0o700)
            live = base / 'live'
            live.mkdir()
            (live / 'config.toml').write_text('do not read this live config')
            env = dict(os.environ, PATH=str(base) + os.pathsep + os.environ['PATH'],
                       XDG_CONFIG_HOME=str(live), XDG_CACHE_HOME=str(live), XDG_STATE_HOME=str(live),
                       PREVIEW_RECORD=str(record), PREVIEW_OUTPUT=output, PREVIEW_STATUS=str(status))
            result = subprocess.run(['python3', str(CAROUSEL / 'preview-palette.py'),
                                     '--request-id', 'preview-42', '--mode', 'dark', str(wallpaper)],
                                    cwd=base, env=env, capture_output=True, text=True, timeout=15)
            recorded = json.loads(record.read_text()) if record.exists() else None
            self.assertEqual([p.name for p in live.iterdir()], ['config.toml'])
            self.assertFalse((base / 'injected').exists())
            if recorded:
                self.assertFalse(Path(recorded['config_path']).exists())
            return result, recorded, str(wallpaper)

    def test_isolated_command_and_current_matugen_json(self):
        result, record, wallpaper = self.run_preview()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record['args'], ['image', wallpaper, '--config', record['config_path'],
                         '--dry-run', '--json', 'hex', '--mode', 'dark', '--prefer',
                         'less-saturation', '--source-color-index', '0', '--quiet'])
        config = tomllib.loads(record['config'])
        self.assertEqual(config['templates'], {})
        self.assertEqual(config['config']['wallpaper'], {'set': False, 'command': ''})
        self.assertTrue(all(value.startswith(str(Path(record['config_path']).parent))
                            for value in record['xdg'].values()))
        self.assertEqual(json.loads(result.stdout), {'schema_version': 1, 'request_id': 'preview-42',
                         'wallpaper': wallpaper, 'mode': 'dark', 'swatches': ['#123456'] * 5})

    def test_failure_invalid_json_and_missing_roles_have_no_preview(self):
        bad_colors = json.dumps({'colors': {role: {'dark': {'color': 'red'}} for role in
                                            ['primary', 'secondary', 'tertiary', 'surface', 'on_surface']}})
        for output, status in [('{}', 0), ('not json', 0), ('{"colors": {}}', 0), (bad_colors, 0), ('{}', 7)]:
            with self.subTest(output=output, status=status):
                result, _, _ = self.run_preview(output, status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertTrue(result.stderr)

    def test_preview_subprocess_timeout_is_bounded(self):
        spec = importlib.util.spec_from_file_location('preview_palette', CAROUSEL / 'preview-palette.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory() as temp:
            wallpaper = Path(temp) / 'wall.png'
            wallpaper.touch()
            with mock.patch.object(helper.subprocess, 'run', side_effect=subprocess.TimeoutExpired('matugen', 8)) as run:
                with self.assertRaises(subprocess.TimeoutExpired):
                    helper.preview(str(wallpaper), 'dark', 'timeout-test')
                self.assertEqual(run.call_args.kwargs['timeout'], 8)
                self.assertFalse(Path(run.call_args.kwargs['cwd']).exists())

    @unittest.skipUnless(shutil.which('matugen'), 'Matugen required for isolated dry-run smoke test')
    def test_real_matugen_dry_run_without_live_writes(self):
        result, _, _ = self.run_preview(real=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['swatches']), 5)


class WrapperTests(unittest.TestCase):
    def run_wrapper(self, status=0, stderr='', notify_status=0, missing=False):
        with tempfile.TemporaryDirectory(prefix="carousel-") as temp:
            base = Path(temp)
            config = base / "config space"
            scripts = config / "hypr/scripts"
            scripts.mkdir(parents=True)
            record = base / "args.json"
            pipeline = scripts / "generate-theme.py"
            if not missing:
                pipeline.write_text(
                    "import json, os, sys\n"
                    "from pathlib import Path\n"
                    "Path(os.environ['ARG_RECORD']).write_text(json.dumps(sys.argv[1:]))\n"
                    "print(os.environ['RESULT_JSON'])\n"
                    "sys.stderr.write(os.environ['PIPELINE_STDERR'])\n"
                    "sys.exit(int(os.environ['PIPELINE_STATUS']))\n"
                )
            notify = base / "notify-send"
            notify.write_text(f"#!/bin/sh\nprintf 'notification noise\\n'\nexit {notify_status}\n")
            notify.chmod(0o700)
            wallpaper = str(base / "Ảnh có dấu ; $(touch injected).png")
            result_json = json.dumps({
                "schema_version": 1, "request_id": "session-42", "wallpaper": wallpaper,
                "status": "applied" if status == 0 else "rolled_back",
                "palette_revision": "a" * 64 if status == 0 else None,
                "error_code": None if status == 0 else "matugen_failed",
            }, ensure_ascii=False)
            env = dict(os.environ, XDG_CONFIG_HOME=str(config), ARG_RECORD=str(record),
                       RESULT_JSON=result_json, PIPELINE_STDERR=stderr,
                       PIPELINE_STATUS=str(status), PATH=str(base) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(
                ["bash", str(CAROUSEL / "apply-wallpaper.sh"), "--request-id", "session-42", wallpaper],
                capture_output=True, text=True, env=env, cwd=base, timeout=10,
            )
            args = json.loads(record.read_text()) if record.exists() else None
            self.assertFalse((base / "injected").exists())
            return result, args, wallpaper, result_json

    def test_forwards_flags_id_and_unicode_path_without_shell_evaluation(self):
        result, args, wallpaper, expected = self.run_wrapper(stderr="diagnostic\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ["--apply-wallpaper", "--request-id", "session-42", "--json", wallpaper])
        self.assertEqual(result.stdout, expected + '\n')
        self.assertEqual(result.stderr, 'diagnostic\n')

    def test_failure_retains_pipeline_json_exit_and_stderr(self):
        result, _, _, expected = self.run_wrapper(status=1, stderr="matugen failure\n", notify_status=23)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, expected + '\n')
        self.assertIn('matugen failure', result.stderr)
        self.assertNotIn('notification noise', result.stdout)

    def test_missing_pipeline_has_no_fabricated_ack(self):
        result, _, _, _ = self.run_wrapper(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertTrue(result.stderr)


@unittest.skipUnless(shutil.which('qs'), 'Quickshell is required for the offscreen Process check')
class QmlProcessTests(unittest.TestCase):
    def test_offscreen_process_acknowledgement(self):
        # No PanelWindow is instantiated; no compositor, wallpaper or theme tool is contacted.
        with tempfile.TemporaryDirectory(prefix='carousel-qml-') as temp:
            base = Path(temp)
            base.chmod(0o700)
            qml = '''
import QtQuick
import Quickshell
import Quickshell.Io
import %s as ApplyState
ShellRoot {
    id: root
    property var state: ApplyState.create('qml-process')
    property int completions: 0
    function send(event) {
        state = ApplyState.reduce(state, event);
        if (!state.active) {
            if (completions < 2 && (state.phase !== 'applied' || state.applied !== '/ảnh có dấu.png'))
                fail('wrong applied path or phase');
            if (completions === 2 && (state.phase !== 'unknown' || state.applied !== ''))
                fail('subprocess failure implied success');
            if (completions === 3 && (state.phase !== 'failed' || state.error !== 'process_start_failed'))
                fail('launch failure was not reported');
            completions++;
            if (completions === 4) Qt.quit();
            else Qt.callLater(start);
        }
    }
    function fail(message) { console.error('CAROUSEL_FAILURE: ' + message); Qt.callLater(Qt.quit); }
    function start() {
        state = ApplyState.create('qml-process-' + completions);
        state = ApplyState.reduce(state, {type: 'request', wallpaper: '/ảnh có dấu.png'});
        process.requestId = state.active.requestId;
        process.didStart = false;
        process.command = ['python3', '-c',
            'import json,sys; print(json.dumps(dict(schema_version=1,request_id=sys.argv[1],wallpaper=sys.argv[2],status="applied",palette_revision="a"*64,error_code=None)))',
            process.requestId, state.active.wallpaper];
        if (completions === 2) process.command = ['python3', '-c', 'import sys; sys.exit(17)'];
        if (completions === 3) process.command = ['/missing-carousel-executable'];
        process.running = true;
        if (completions === 3) startWatch.restart();
    }
    Process {
        id: process
        property string requestId: ''
        property bool didStart: false
        onStarted: didStart = true
        stdout: StdioCollector {
            onStreamFinished: root.send({type: 'stdout', requestId: process.requestId, text: text})
        }
        onExited: (exitCode, exitStatus) => root.send({type: 'exit', requestId: requestId,
            code: exitCode, exitStatus: exitStatus})
    }
    Timer {
        id: startWatch
        interval: 250
        onTriggered: {
            if (!process.didStart && !process.running)
                root.send({type: 'launch_failed', requestId: process.requestId});
        }
    }
    Timer { interval: 5000; running: true; onTriggered: root.fail('ack timeout') }
    Component.onCompleted: {
        let preview = ApplyState.createPreview('qml-preview');
        preview = ApplyState.selectPreview(preview, '/ảnh old.png', 'dark');
        const old = preview;
        preview = ApplyState.selectPreview(preview, '/ảnh latest.png', 'light');
        const result = p => JSON.stringify({schema_version: 1, request_id: p.requestId,
            wallpaper: p.wallpaper, mode: p.mode,
            swatches: ['#123456', '#234567', '#345678', '#456789', '#567890']});
        preview = ApplyState.finishPreview(preview, old.requestId, result(old), 0, 0);
        if (preview.phase !== 'pending' || preview.swatches.length) fail('stale preview accepted');
        preview = ApplyState.finishPreview(preview, preview.requestId, result(preview), 0, 0);
        if (preview.phase !== 'ready' || preview.wallpaper !== '/ảnh latest.png') fail('latest preview lost');
        start();
    }
}
''' % json.dumps('ApplyState.js')
            (base / 'ApplyState.js').write_text((CAROUSEL / 'ApplyState.js').read_text())
            (base / 'shell.qml').write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion',
                       QML_DISABLE_DISK_CACHE='1', XDG_RUNTIME_DIR=temp,
                       WAYLAND_DISPLAY='', DISPLAY='')
            result = subprocess.run(['qs', '-p', str(base / 'shell.qml')], env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('CAROUSEL_FAILURE', result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('sha256sum'), 'sha256sum required for native revision check')
    def test_offscreen_hash_process_rejects_obsolete_generation(self):
        with tempfile.TemporaryDirectory(prefix='carousel-hash-') as temp:
            base = Path(temp)
            base.chmod(0o700)
            native = base / 'native palette Ảnh.json'
            native.write_bytes(b'{"native": "raw bytes, including whitespace"}\n')
            expected = hashlib.sha256(native.read_bytes()).hexdigest()
            source = '''
import QtQuick
import Quickshell
import Quickshell.Io
import "ApplyState.js" as ApplyState
ShellRoot {
    id: root
    property bool gotOutput: false
    property string output: ''
    property int code: -1
    property int status: -1
    function check() {
        if (!gotOutput || code < 0) return;
        if (ApplyState.paletteRevision(2, 1, output, code, status) !== null)
            console.error('CAROUSEL_FAILURE: obsolete hash accepted');
        if (ApplyState.paletteRevision(2, 2, output, code, status) !== %s)
            console.error('CAROUSEL_FAILURE: actual file digest mismatch');
        Qt.callLater(Qt.quit);
    }
    Process {
        command: ['sha256sum', '--zero', '--', %s]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { root.output = text; root.gotOutput = true; root.check(); }
        }
        onExited: (exitCode, exitStatus) => { root.code = exitCode; root.status = exitStatus; root.check(); }
    }
    Timer { interval: 3000; running: true; onTriggered: {
        console.error('CAROUSEL_FAILURE: hash timeout'); Qt.quit();
    } }
}
''' % (json.dumps(expected), json.dumps(str(native)))
            (base / 'ApplyState.js').write_text((CAROUSEL / 'ApplyState.js').read_text())
            (base / 'shell.qml').write_text(source)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion',
                       QML_DISABLE_DISK_CACHE='1', XDG_RUNTIME_DIR=temp, WAYLAND_DISPLAY='', DISPLAY='')
            result = subprocess.run(['qs', '-p', str(base / 'shell.qml')], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('CAROUSEL_FAILURE', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
