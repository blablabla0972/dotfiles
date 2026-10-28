"""Preview must install sources without changing native session state."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RiceInstallTest(unittest.TestCase):
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
