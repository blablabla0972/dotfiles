"""Preview snapshots must bind cache keys to the bytes Matugen renders."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'config/quickshell/wallpaper-switcher/preview-palette.py'
spec = importlib.util.spec_from_file_location('preview_snapshot', SOURCE)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
ROLES = ('primary', 'secondary', 'tertiary', 'surface', 'on_surface')
A = b'P6\n1 1\n255\n' + bytes([170, 170, 170])
B = b'P6\n1 1\n255\n' + bytes([187, 187, 187])


def palette(color):
    return SimpleNamespace(stdout=json.dumps({'colors': {
        role: {'dark': {'color': color}} for role in ROLES}}))


class PreviewSnapshotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.image = self.root / 'original.ppm'
        self.image.write_bytes(A)
        self.binary = self.root / 'matugen'
        self.binary.write_bytes(b'identity only; never executed')
        self.cache = self.root / 'cache'
        for patcher in (
            patch.dict(os.environ, {'XDG_CACHE_HOME': str(self.cache)}),
            patch.object(preview.shutil, 'which', return_value=str(self.binary)),
            patch.object(preview, 'TemporaryDirectory',
                         side_effect=lambda **kw: tempfile.TemporaryDirectory(dir=self.root, **kw)),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def replace_source(self, data):
        incoming = self.root / 'incoming.ppm'
        incoming.write_bytes(data)
        os.replace(incoming, self.image)

    def test_aba_replacement_cannot_poison_later_cache_hit(self):
        rendered_paths = []

        def render(cmd, **kwargs):
            self.replace_source(B)
            source = Path(cmd[2])
            rendered_paths.append(source)
            response = palette('#bbbbbb' if source.read_bytes() == B else '#aaaaaa')
            self.replace_source(A)
            return response

        with patch.object(preview.subprocess, 'run', side_effect=render):
            first = preview.preview(str(self.image), 'dark', 'first')
        with patch.object(preview.subprocess, 'run', return_value=palette('#aaaaaa')) as run:
            second = preview.preview(str(self.image), 'dark', 'fresh-request')
        self.assertEqual(second['swatches'], ['#aaaaaa'] * 5)
        self.assertEqual(first['swatches'], second['swatches'])
        self.assertEqual(second['request_id'], 'fresh-request')
        self.assertEqual(second['wallpaper'], str(self.image))
        self.assertEqual(self.image.read_bytes(), A)
        self.assertEqual(run.call_count, 0)
        self.assertNotEqual(rendered_paths[0], self.image)
        self.assertFalse(rendered_paths[0].exists())
        self.assertEqual(list(self.root.glob('wallpaper-preview-*')), [])

    def test_render_failures_leave_no_snapshot_or_cache(self):
        for failure in (subprocess.TimeoutExpired('matugen', 8),
                        subprocess.CalledProcessError(1, 'matugen'), ValueError('invalid JSON')):
            with self.subTest(failure=type(failure).__name__):
                def fail(cmd, **kwargs):
                    self.assertEqual(Path(cmd[2]).read_bytes(), A)
                    raise failure
                with patch.object(preview.subprocess, 'run', side_effect=fail):
                    with self.assertRaises(type(failure)):
                        preview.preview(str(self.image), 'dark', 'failed')
                self.assertEqual(list(self.root.glob('wallpaper-preview-*')), [])
                self.assertEqual(list(self.cache.rglob('*')), [])
                self.assertEqual(self.image.read_bytes(), A)


if __name__ == '__main__':
    unittest.main()
