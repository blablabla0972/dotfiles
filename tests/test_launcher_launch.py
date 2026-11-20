"""Execute the launch wrapper with real argv, cwd and failed service registration."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'config/quickshell/rice-shell/launcher/LaunchCommand.js'


@unittest.skipUnless(shutil.which('node'), 'node required')
class LauncherLaunchTests(unittest.TestCase):
    def context(self, app, home, terminal='kitty'):
        script = SOURCE.read_text().replace('.pragma library', '')
        script += '\nconsole.log(JSON.stringify(launchContext(' + ','.join(
            json.dumps(v) for v in (app, terminal, str(home))) + ')));'
        return json.loads(subprocess.check_output(['node', '-e', script], text=True))

    def test_service_launch_keeps_literal_arguments_and_working_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fake = base / 'systemd-run'
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > service-args\n')
            fake.chmod(0o755)
            literal = 'spaces $(touch SHOULD_NOT_EXIST); `touch BAD`'
            ctx = self.context({'command': ['/bin/echo', literal],
                                'workingDirectory': tmp}, base)
            env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'])
            subprocess.run(ctx['command'], cwd=ctx['workingDirectory'], env=env, check=True)
            args = (base / 'service-args').read_text().splitlines()
            self.assertEqual(args[-2:], ['/bin/echo', literal])
            self.assertIn('--working-directory=' + tmp, args)
            self.assertIn('--service-type=exec', args)
            self.assertIn('--property=ExitType=cgroup', args)
            self.assertFalse((base / 'SHOULD_NOT_EXIST').exists())
            self.assertFalse((base / 'BAD').exists())

    def test_failed_service_registration_falls_back_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fake = base / 'systemd-run'
            fake.write_text('#!/bin/sh\nexit 1\n')
            fake.chmod(0o755)
            ctx = self.context({'command': ['/bin/printf', '%s', 'fallback once']}, base)
            env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'])
            result = subprocess.run(ctx['command'], cwd=ctx['workingDirectory'],
                                    env=env, capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, 'fallback once')

    def test_terminal_entries_are_wrapped_and_default_to_home(self):
        ctx = self.context({'command': ['btop', '--utf-force'], 'runInTerminal': True}, '/tmp')
        self.assertEqual(ctx['command'][-4:], ['kitty', '-e', 'btop', '--utf-force'])
        self.assertEqual(ctx['workingDirectory'], '/tmp')

    def test_empty_command_cannot_launch(self):
        self.assertIsNone(self.context({'command': []}, '/tmp'))

    @unittest.skipUnless(shutil.which('systemd-run') and shutil.which('systemctl'),
                         'systemd user manager required')
    def test_real_service_preserves_dollar_variables_in_arguments(self):
        if subprocess.run(['systemctl', '--user', 'show-environment'],
                          capture_output=True).returncode:
            self.skipTest('systemd user manager unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            shim = base / 'systemd-run'
            shim.write_text('#!/bin/sh\nexec ' + shutil.which('systemd-run')
                            + ' --wait --pipe "$@"\n')
            shim.chmod(0o755)
            literal = '$HOME/${USER}'
            ctx = self.context({'command': ['/bin/printf', '%s', literal]}, base)
            env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'])
            result = subprocess.run(ctx['command'], cwd=ctx['workingDirectory'],
                                    env=env, capture_output=True, text=True, timeout=8, check=True)
            self.assertEqual(result.stdout, literal)

    def test_repeated_activation_during_close_only_launches_once(self):
        source = (SOURCE.parent / 'Launcher.qml').read_text()
        functions = []
        for name in ('launchSelected', 'dismiss'):
            body = re.search(r'    function ' + name + r'\(\): void \{.*?\n    \}',
                             source, re.S).group()
            functions.append(body.replace('(): void', '()'))
        script = SOURCE.read_text().replace('.pragma library', '') + '''
const LaunchCommand = {launchContext};
let visible = true, closing = false, count = 0, timerStarts = 0;
let searchText = "kitty", selectedIndex = 0;
const calculatorMode = false, actionsMode = false;
const filteredApps = [{command:["kitty"], execute() {count++;}}];
const Quickshell = {env:() => "/tmp", execDetached:() => {count++;}};
const closeTimer = {restart:() => {timerStarts++;}};
''' + '\n'.join(functions) + '''
launchSelected(); launchSelected();
console.log(JSON.stringify({count, closing, visible, timerStarts}));
'''
        result = json.loads(subprocess.check_output(['node', '-e', script], text=True))
        self.assertEqual(result, {'count': 1, 'closing': True, 'visible': True, 'timerStarts': 1})


if __name__ == '__main__':
    unittest.main()
