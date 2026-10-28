"""Preview must install sources without changing native session state."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RiceInstallTest(unittest.TestCase):
    def test_default_and_all_no_state_install_sources_preserve_settings(self):
        for options in ([], ['--no-state'], ['--all', '--no-state']):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                repo, home, stub = [root / name for name in ('repo', 'home', 'stub')]
                stub.mkdir()
                # --all may request daemon-reload: keep every process in this fixture.
                (stub / 'systemctl').write_text('#!/bin/sh\nexit 0\n')
                (stub / 'systemctl').chmod(0o700)
                for name in ('hypr', 'noctalia', 'rice'):
                    (repo / 'config' / name).mkdir(parents=True)
                (repo / 'state/noctalia').mkdir(parents=True)
                (repo / 'state/noctalia/settings.toml').write_text('snapshot settings')
                shutil.copy2(ROOT / 'install.sh', repo / 'install.sh')
                state = home / '.local/state/noctalia/settings.toml'
                state.parent.mkdir(parents=True)
                state.write_text('live lock layout')
                result = subprocess.run(['bash', str(repo / 'install.sh'), *options], capture_output=True,
                                        text=True, env={**os.environ, 'HOME': str(home),
                                        'PATH': str(stub) + os.pathsep + os.environ['PATH']})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state.read_text(), 'live lock layout')
                self.assertFalse(state.is_symlink())
                for name in ('hypr', 'noctalia', 'rice'):
                    self.assertEqual((home / '.config' / name).resolve(), repo / 'config' / name)

    def test_selected_no_state_preview_preserves_native_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            state = home / '.local/state/noctalia/settings.toml'
            state.parent.mkdir(parents=True)
            state.write_text('user native lock settings')
            result = subprocess.run(['bash', str(ROOT / 'install.sh'), '--no-state', 'hypr', 'noctalia', 'rice'],
                                    env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state.read_text(), 'user native lock settings')
            self.assertFalse(state.is_symlink())
            for name in ('hypr', 'noctalia', 'rice'):
                self.assertEqual((home / '.config' / name).resolve(), ROOT / 'config' / name)


if __name__ == '__main__':
    unittest.main()
