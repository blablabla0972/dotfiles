"""Cached rendering must skip Matugen without restoring stale or damaged outputs."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cached_theme', ROOT / 'config/hypr/scripts/generate-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class MatugenCacheTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config = self.root / 'config'
        self.cache = self.root / 'cache'
        self.image = self.root / 'Ảnh.png'
        self.image.write_bytes(b'image-one')
        self.binary = self.root / 'matugen'
        self.binary.write_bytes(b'version-one')
        self.template = self.config / 'matugen/template'
        self.template.parent.mkdir(parents=True)
        self.template.write_text('template-one')
        self.source = self.config / 'matugen/config.toml'
        self.source.write_text('\n'.join(
            f'[templates.output{i}]\ninput_path={json.dumps(str(self.template))}\n'
            f'output_path={json.dumps(str(self.config / name))}\n'
            for i, name in enumerate(theme.MATUGEN_OUTPUTS)))
        self.calls = 0
        for manager in [patch.dict(os.environ, XDG_CACHE_HOME=str(self.cache)),
                        patch.object(theme.shutil, 'which', return_value=str(self.binary)),
                        patch.object(theme, 'command', side_effect=self.generate)]:
            manager.start()
            self.addCleanup(manager.stop)

    def generate(self, argv):
        self.calls += 1
        for name in theme.MATUGEN_OUTPUTS:
            path = self.config / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f'{name}: render {self.calls}\r\n'.encode())
        return ''

    def render(self, mode='dark'):
        theme.render_matugen(self.image, self.config, mode)

    def test_hit_restores_all_outputs_and_preserves_leaf_symlinks(self):
        self.render()
        expected = {name: (self.config / name).read_bytes() for name in theme.MATUGEN_OUTPUTS}
        target = self.root / 'linked-output'
        link = self.config / theme.MATUGEN_OUTPUTS[0]
        link.unlink()
        target.write_text('overwritten')
        target.chmod(0o640)
        link.symlink_to(target)
        (self.config / theme.MATUGEN_OUTPUTS[1]).unlink()
        self.render()
        self.assertEqual(self.calls, 1, 'Cache hit must not execute Matugen')
        self.assertTrue(link.is_symlink())
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        self.assertEqual({name: (self.config / name).read_bytes() for name in expected}, expected)

    def test_image_mode_template_config_and_binary_changes_invalidate(self):
        self.render()
        stamp = self.image.stat()
        self.image.write_bytes(b'image-two')
        os.utime(self.image, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.render()
        self.assertEqual(self.calls, 2, 'Same path/mtime must not hide new image contents')
        self.render('light')
        self.template.write_text('template-two')
        self.render('light')
        self.source.write_text(self.source.read_text() + '\n# new config\n')
        self.render('light')
        self.binary.write_bytes(b'version-two-new')
        self.render('light')
        self.assertEqual(self.calls, 6)
        with patch.object(theme, 'MATUGEN_FLAGS', (*theme.MATUGEN_FLAGS, '--new-option')):
            self.render('light')
        self.assertEqual(self.calls, 7)
        self.render('light')
        self.assertEqual(self.calls, 7)

    def test_corrupt_or_incomplete_cache_regenerates(self):
        self.render()
        entries = list(self.cache.rglob('*.json'))
        self.assertEqual(len(entries), 1)
        for bad in ['not json', '{"schema_version":1,"outputs":{}}']:
            entries[0].write_text(bad)
            self.render()
        self.assertEqual(self.calls, 3)

    def test_unavailable_cache_does_not_break_rendering(self):
        self.cache.write_text('not a directory')
        self.render()
        self.render()
        self.assertEqual(self.calls, 2)

    def test_failed_generation_is_not_cached(self):
        with patch.object(theme, 'command', side_effect=RuntimeError('generation failed')):
            with self.assertRaises(RuntimeError):
                self.render()
        self.assertEqual(list(self.cache.rglob('*.json')), [])

    def test_input_changed_during_generation_is_not_cached(self):
        def changing(argv):
            self.generate(argv)
            self.image.write_bytes(b'changed while Matugen ran')
        with patch.object(theme, 'command', side_effect=changing):
            self.render()
        self.assertEqual(list(self.cache.rglob('*.json')), [])


if __name__ == '__main__':
    unittest.main()
