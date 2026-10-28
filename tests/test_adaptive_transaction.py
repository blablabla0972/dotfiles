"""Exercise the real transaction with desktop commands replaced at the IPC edge."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from time import sleep as real_sleep
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('adaptive_transaction', ROOT / 'config/hypr/scripts/generate-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class AdaptiveTransactionTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config, self.state, self.runtime = [self.root / p for p in ('config', 'state', 'runtime')]
        self.runtime.mkdir()
        for app in ('hypr', 'noctalia/palettes', 'micro/colorschemes', 'kitty/themes'):
            (self.config / app).mkdir(parents=True)
        self.old = self.root / 'old.png'
        self.old.write_bytes(b'old wallpaper')
        self.wallpaper = self.root / 'ảnh mới có khoảng trắng.png'
        self.wallpaper.write_bytes(b'new wallpaper')
        self.link = self.config / 'hypr/current_wallpaper'
        self.link.symlink_to(self.old)
        self.raw = self.config / 'noctalia/palettes/matugen.json'
        self.palette = json.loads((ROOT / 'config/noctalia/palettes/matugen.json').read_text())
        self.raw.write_text(json.dumps(self.palette))
        self.native = self.config / 'kitty/themes/noctalia.conf'
        self.native.write_text('old native')
        self.tokens = self.state / 'desktop-wallpaper/adaptive-theme.json'
        self.tokens.parent.mkdir(parents=True)
        self.tokens.write_text('old adaptive')
        self.tokens.chmod(0o640)
        self.mode, self.selected = 'dark', str(self.old)
        self.calls = []
        self.failure = None
        self.env = patch.dict(os.environ, {
            'XDG_CONFIG_HOME': str(self.config), 'XDG_STATE_HOME': str(self.state),
            'XDG_DATA_HOME': str(self.root / 'data'), 'XDG_RUNTIME_DIR': str(self.runtime),
            'HYPRLAND_INSTANCE_SIGNATURE': 'test', 'NOCTALIA_WALLPAPER_PATH': str(self.wallpaper),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        for name, value in [('command', self.command), ('render_matugen', self.render),
                            ('stage_native', self.stage), ('quiesce_shell', lambda: False)]:
            p = patch.object(theme, name, side_effect=value)
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(theme.time, 'sleep')
        p.start()
        self.addCleanup(p.stop)

    def render(self, wallpaper, config, mode):
        self.raw.write_text(json.dumps(self.palette, sort_keys=True))
        for name in ('hypr/colors.conf', 'micro/colorschemes/adaptive.micro'):
            (self.config / name).write_text(mode)
        if self.failure == 'matugen':
            raise RuntimeError('injected matugen failure after partial output')

    def stage(self, *args):
        if self.failure == 'stage':
            raise RuntimeError('injected native template staging failure')
        return {str(self.native): hashlib.sha256(self.mode.encode()).hexdigest()}

    def command(self, argv, **kwargs):
        self.calls.append(argv)
        if argv[:3] == ['noctalia', 'config', 'export']:
            return f'[theme]\nmode="{self.mode}"\nsource="wallpaper"\nmatugen_palette="matugen"\n[wallpaper]\nenabled=false\n'
        if argv[:2] == ['noctalia', 'theme']:
            return json.dumps({mode: {k: '#ffffff' for k in (
                'primary', 'surface', 'on_surface', 'secondary', 'on_secondary', 'error', 'on_error')}
                for mode in ('dark', 'light')})
        if argv[:2] == ['noctalia', 'msg']:
            if argv[2] == 'theme-mode-get': return self.mode
            if argv[2] == 'wallpaper-get': return self.selected
            if argv[2] == 'wallpaper-set': self.selected = argv[3]
            if argv[2] == 'templates-apply':
                self.native.write_text(self.mode)
                if self.failure == 'templates': raise RuntimeError('injected native apply failure')
            return ''
        if argv[0] == 'hyprctl':
            if self.failure == 'hyprland' and argv[1] == 'configerrors': return 'injected config error'
            return ''
        if argv[0] == 'gsettings': return "'prefer-dark'"
        if argv[0] == 'swww': return ''
        raise AssertionError(argv)

    def invoke(self, *options, wallpaper=None):
        args = [str(theme.__file__), '--apply-wallpaper', '--request-id', 'test_request_01', '--json',
                str(self.wallpaper if wallpaper is None else wallpaper), *options]
        output = io.StringIO()
        diagnostics = io.StringIO()
        with patch('sys.argv', args), contextlib.redirect_stdout(output), contextlib.redirect_stderr(diagnostics):
            try: code = theme.main()
            except SystemExit as e: code = e.code
        self.diagnostics = diagnostics.getvalue()
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 1, output.getvalue())
        return code, json.loads(lines[0])

    def test_success_acknowledges_the_committed_palette_and_unicode_path(self):
        code, record = self.invoke()
        self.assertEqual(code, 0)
        self.assertEqual(set(record), {'schema_version', 'request_id', 'status', 'wallpaper', 'palette_revision', 'error_code'})
        self.assertEqual(record['request_id'], 'test_request_01')
        self.assertEqual(record['status'], 'applied')
        self.assertEqual(record['wallpaper'], str(self.wallpaper))
        self.assertIsNone(record['error_code'])
        revision = hashlib.sha256(self.raw.read_bytes()).hexdigest()
        self.assertEqual(record['palette_revision'], revision)
        tokens = json.loads(self.tokens.read_text())
        self.assertEqual(tokens['source_palette_sha256'], revision)
        self.assertEqual(tokens['wallpaper_sha256'], hashlib.sha256(self.wallpaper.read_bytes()).hexdigest())
        self.assertEqual(self.link.resolve(), self.wallpaper)
        self.assertEqual(self.tokens.stat().st_mode & 0o777, 0o640)

    def test_invalid_wallpaper_does_not_touch_outputs(self):
        before = self.raw.read_bytes()
        code, record = self.invoke(wallpaper=self.root / 'missing.png')
        self.assertEqual((code, record['status'], record['error_code']), (1, 'failed', 'invalid_wallpaper'))
        self.assertEqual(self.raw.read_bytes(), before)
        self.assertEqual(self.tokens.read_text(), 'old adaptive')
        self.assertFalse(self.calls)

    def test_failed_steps_restore_old_palette_tokens_and_wallpaper_link(self):
        for failure in ('matugen', 'stage', 'templates'):
            with self.subTest(failure=failure):
                before = self.raw.read_bytes()
                self.failure = failure
                code, record = self.invoke()
                self.assertEqual((code, record['status']), (1, 'rolled_back'))
                self.assertEqual(record['palette_revision'], hashlib.sha256(before).hexdigest())
                self.assertEqual(self.raw.read_bytes(), before)
                self.assertEqual(self.tokens.read_text(), 'old adaptive')
                self.assertEqual(self.native.read_text(), 'old native')
                self.assertEqual(self.link.resolve(), self.old)

    def test_persistent_compositor_errors_make_rollback_incomplete(self):
        self.failure = 'hyprland'
        code, record = self.invoke()
        self.assertEqual((code, record['status'], record['error_code']),
                         (1, 'failed', 'rollback_incomplete'))
        self.assertIsNone(record['palette_revision'])
        self.assertIn('Rollback incomplete', self.diagnostics)
        self.assertNotIn('RESTORED_SNAPSHOT', self.diagnostics)

    def test_restart_failures_make_rollback_incomplete(self):
        self.failure = 'templates'
        for failure in ('launch', 'exit', 'exit_after_ipc', 'socket', 'invalid_status', 'timeout'):
            with self.subTest(failure=failure):
                launcher = Mock()
                launcher.poll.return_value = 17 if failure == 'exit' else 0
                if failure == 'exit_after_ipc': launcher.poll.side_effect = [None, 17]
                attempts = []
                def ipc(argv, **kwargs):
                    if argv == ['noctalia', 'msg', 'status']:
                        attempts.append(kwargs.get('timeout'))
                        if failure in ('exit', 'exit_after_ipc'): return '{"locked": false}'
                        if failure == 'invalid_status': return '[]'
                        if failure == 'timeout':
                            raise theme.subprocess.TimeoutExpired(argv, .5)
                        raise RuntimeError('socket unavailable')
                    return self.command(argv, **kwargs)
                with patch.object(theme, 'quiesce_shell', return_value=True), \
                     patch.object(theme.subprocess, 'Popen', return_value=launcher,
                                  side_effect=OSError('launch denied') if failure == 'launch' else None), \
                     patch.object(theme, 'command', side_effect=ipc):
                    code, record = self.invoke()
                self.assertEqual((code, record['status'], record['error_code']),
                                 (1, 'failed', 'rollback_incomplete'))
                self.assertIsNone(record['palette_revision'])
                self.assertIn('Rollback incomplete', self.diagnostics)
                self.assertNotIn('RESTORED_SNAPSHOT', self.diagnostics)
                self.assertEqual(self.tokens.read_text(), 'old adaptive')
                if failure in ('socket', 'invalid_status', 'timeout'):
                    self.assertGreater(len(attempts), 0)
                    self.assertLessEqual(len(attempts), 20)
                    self.assertTrue(all(0 < timeout <= 1 for timeout in attempts))

    def test_compositor_is_verified_after_restart_readiness(self):
        self.failure = 'templates'
        launcher = Mock()
        launcher.poll.return_value = 0
        ready = False
        def ipc(argv, **kwargs):
            nonlocal ready
            if argv == ['noctalia', 'msg', 'status']:
                ready = True
                return '{"locked": false}'
            if ready and argv == ['hyprctl', 'configerrors']:
                return 'restart triggered config error'
            return self.command(argv, **kwargs)
        with patch.object(theme, 'quiesce_shell', return_value=True), \
             patch.object(theme.subprocess, 'Popen', return_value=launcher), \
             patch.object(theme, 'command', side_effect=ipc):
            code, record = self.invoke()
        self.assertEqual((code, record['status'], record['error_code']),
                         (1, 'failed', 'rollback_incomplete'))
        self.assertIn('restart triggered config error', self.diagnostics)
        self.assertNotIn('RESTORED_SNAPSHOT', self.diagnostics)

    def test_restart_waits_for_socket_with_running_or_daemonized_launcher(self):
        self.failure = 'templates'
        for exit_code in (None, 0):
            with self.subTest(exit_code=exit_code):
                launcher = Mock()
                launcher.poll.return_value = exit_code
                replies = iter([RuntimeError('socket unavailable'), '{"locked": false}'])
                def ipc(argv, **kwargs):
                    if argv == ['noctalia', 'msg', 'status']:
                        reply = next(replies)
                        if isinstance(reply, Exception): raise reply
                        return reply
                    return self.command(argv, **kwargs)
                with patch.object(theme, 'quiesce_shell', return_value=True), \
                     patch.object(theme.subprocess, 'Popen', return_value=launcher), \
                     patch.object(theme, 'command', side_effect=ipc):
                    code, record = self.invoke()
                self.assertEqual((code, record['status']), (1, 'rolled_back'))
                self.assertEqual(list(replies), [], 'recovery must wait for socket readiness')
                self.assertIn('RESTORED_SNAPSHOT', self.diagnostics)
                self.assertNotIn('Rollback incomplete', self.diagnostics)

    def test_restart_still_attempted_after_file_recovery_failure(self):
        self.failure = 'templates'
        launcher = Mock()
        launcher.poll.return_value = 0
        ready = []
        def ipc(argv, **kwargs):
            if argv == ['noctalia', 'msg', 'status']:
                ready.append(True)
                return '{"locked": false}'
            return self.command(argv, **kwargs)
        with patch.object(theme, 'quiesce_shell', return_value=True), \
             patch.object(theme.Snapshot, 'restore', side_effect=OSError('restore denied')), \
             patch.object(theme.subprocess, 'Popen', return_value=launcher), \
             patch.object(theme, 'command', side_effect=ipc):
            code, record = self.invoke()
        self.assertEqual((code, record['status'], record['error_code']),
                         (1, 'failed', 'rollback_incomplete'))
        self.assertIn('restore denied', self.diagnostics)
        self.assertTrue(ready)

    def test_token_publication_error_rolls_back_all_managed_outputs(self):
        original = theme.atomic_write
        failed = False
        def write(path, data):
            nonlocal failed
            if path == self.tokens and not failed:
                failed = True
                raise PermissionError('injected adaptive output permission error')
            return original(path, data)
        before = self.raw.read_bytes()
        with patch.object(theme, 'atomic_write', side_effect=write):
            code, record = self.invoke()
        self.assertTrue(failed)
        self.assertEqual((code, record['status']), (1, 'rolled_back'))
        self.assertEqual(self.raw.read_bytes(), before)
        self.assertEqual(self.tokens.read_text(), 'old adaptive')
        self.assertEqual(self.link.resolve(), self.old)

    def test_incomplete_rollback_is_never_reported_as_rolled_back(self):
        self.failure = 'templates'
        with patch.object(theme.Snapshot, 'restore', side_effect=OSError('restore denied')):
            code, record = self.invoke()
        self.assertEqual((code, record['status'], record['error_code']), (1, 'failed', 'rollback_incomplete'))
        self.assertIsNone(record['palette_revision'])

    def test_unknown_previous_wallpaper_cannot_claim_complete_rollback(self):
        self.old.unlink()
        self.failure = 'templates'
        code, record = self.invoke()
        self.assertEqual((code, record['status'], record['error_code']), (1, 'failed', 'rollback_incomplete'))
        self.assertEqual(self.tokens.read_text(), 'old adaptive')

    def test_invalid_request_id_is_rejected_before_transaction(self):
        code, record = self.invoke('--request-id', '../bad\nrequest')
        self.assertEqual((code, record['status'], record['error_code']), (1, 'failed', 'invalid_request'))
        self.assertFalse(self.calls)

    def test_mode_hook_publishes_matching_tokens_without_changing_wallpaper(self):
        self.selected, self.mode = str(self.wallpaper), 'light'
        with patch('sys.argv', [str(theme.__file__), '--theme-mode-changed']):
            self.assertEqual(theme.main(), 0)
        self.assertEqual(json.loads(self.tokens.read_text())['mode'], 'light')
        self.assertEqual(self.link.resolve(), self.old)
        self.assertFalse(any(args[0] == 'swww' for args in self.calls))

    def test_failure_removes_a_new_artifact_instead_of_leaving_partial_state(self):
        self.tokens.unlink()
        self.failure = 'templates'
        code, record = self.invoke()
        self.assertEqual((code, record['status']), (1, 'rolled_back'))
        self.assertFalse(self.tokens.exists())

    @unittest.skipUnless(hasattr(os, 'fork'), 'POSIX process isolation required')
    def test_competing_processes_serialize_complete_palette_and_mode_commits(self):
        trace = self.root / 'writer-trace'
        trace.write_text('')
        original_write = theme.atomic_write
        def event(kind):
            with trace.open('a') as stream:
                stream.write(f'{kind} {self.mode}\n')
        def render(*args):
            event('start')
            self.render(*args)
            real_sleep(.03)  # Force overlap if the actual main() lock is removed.
        def write(path, data):
            original_write(path, data)
            if path == self.tokens:
                event('commit')
        children = []
        with patch.object(theme, 'render_matugen', side_effect=render), patch.object(theme, 'atomic_write', side_effect=write):
            for index, mode in enumerate(('light', 'dark', 'light')):
                image = self.root / f'{index} ảnh.png'
                image.write_bytes(f'image{index}'.encode())
                result_path = self.root / f'result-{index}.json'
                pid = os.fork()
                if pid == 0:
                    try:
                        self.mode, self.wallpaper = mode, image
                        self.palette = copy.deepcopy(self.palette)
                        self.palette[mode]['mPrimary'] = ('#88ccaa', '#aaccee', '#cc99aa')[index]
                        code, record = self.invoke('--request-id', f'competing_{index}')
                        result_path.write_text(json.dumps({'code': code, 'record': record}))
                        os._exit(0)
                    except BaseException as error:
                        result_path.write_text(repr(error))
                        os._exit(1)
                children.append((pid, result_path))
            for pid, result_path in children:
                _, status = os.waitpid(pid, 0)
                self.assertEqual(os.waitstatus_to_exitcode(status), 0, result_path.read_text())
                result = json.loads(result_path.read_text())
                self.assertEqual((result['code'], result['record']['status']), (0, 'applied'))
        events = trace.read_text().splitlines()
        self.assertEqual(len(events), 6)
        for index in range(0, 6, 2):
            self.assertEqual(events[index].split()[0], 'start')
            self.assertEqual(events[index + 1], events[index].replace('start', 'commit', 1))
        tokens = json.loads(self.tokens.read_text())
        self.assertEqual(tokens['mode'], events[-1].split()[1])
        self.assertEqual(tokens['source_palette_sha256'], hashlib.sha256(self.raw.read_bytes()).hexdigest())
        self.assertEqual(tokens['wallpaper_sha256'], hashlib.sha256(self.link.resolve().read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
