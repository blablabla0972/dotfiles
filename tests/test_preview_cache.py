"""Unit tests for preview palette stdlib disk cache."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / 'config/quickshell/wallpaper-switcher/preview-palette.py'

spec = importlib.util.spec_from_file_location('preview_palette', MODULE_PATH)
preview_palette = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview_palette)


class PreviewCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)

        self.cache_dir = self.root / 'cache'
        self.image = self.root / 'test_wall.png'
        self.image.write_bytes(b'image-data-version-1')

        self.binary = self.root / 'matugen'
        self.binary.write_bytes(b'matugen-dummy-binary-1')

        self.swatches_dark = ['#112233', '#223344', '#334455', '#445566', '#556677']
        self.swatches_light = ['#aabbcc', '#bbccdd', '#ccddee', '#ddeeff', '#eeffff']

        self.subprocess_calls = 0

        patcher_cache = patch.dict(os.environ, {'XDG_CACHE_HOME': str(self.cache_dir)})
        patcher_cache.start()
        self.addCleanup(patcher_cache.stop)

        patcher_which = patch.object(preview_palette.shutil, 'which', return_value=str(self.binary))
        patcher_which.start()
        self.addCleanup(patcher_which.stop)

        patcher_run = patch.object(preview_palette.subprocess, 'run', side_effect=self.fake_matugen_run)
        patcher_run.start()
        self.addCleanup(patcher_run.stop)

    def fake_matugen_run(self, cmd, **kwargs):
        self.subprocess_calls += 1
        mode_idx = cmd.index('--mode') + 1
        mode = cmd[mode_idx]
        swatches = self.swatches_dark if mode == 'dark' else self.swatches_light
        roles = ('primary', 'secondary', 'tertiary', 'surface', 'on_surface')
        colors = {
            role: {
                mode: {'color': swatches[i]}
            }
            for i, role in enumerate(roles)
        }
        stdout = json.dumps({'colors': colors})

        class FakeCompletedProcess:
            def __init__(self, out):
                self.stdout = out
                self.returncode = 0

        return FakeCompletedProcess(stdout)

    def test_cache_hit_skips_matugen_and_preserves_fresh_request_identity(self):
        resp1 = preview_palette.preview(str(self.image), 'dark', 'req-001')
        self.assertEqual(self.subprocess_calls, 1)
        self.assertEqual(resp1['request_id'], 'req-001')
        self.assertEqual(resp1['wallpaper'], str(self.image.resolve()))
        self.assertEqual(resp1['swatches'], self.swatches_dark)

        # Second call: different request ID and relative path to same image
        rel_path = os.path.relpath(self.image, os.getcwd())
        resp2 = preview_palette.preview(rel_path, 'dark', 'req-002')
        self.assertEqual(self.subprocess_calls, 1, 'Valid cache hit must not execute Matugen')
        self.assertEqual(resp2['request_id'], 'req-002', 'Returned envelope must retain fresh request_id')
        self.assertEqual(resp2['wallpaper'], str(self.image.resolve()), 'Returned envelope must have absolute path')
        self.assertEqual(resp2['swatches'], self.swatches_dark)

    def test_invalidation_on_changed_image_mode_and_generator(self):
        # 1. Initial generation
        preview_palette.preview(str(self.image), 'dark', 'req-1')
        self.assertEqual(self.subprocess_calls, 1)

        # 2. Mode changed -> miss
        preview_palette.preview(str(self.image), 'light', 'req-2')
        self.assertEqual(self.subprocess_calls, 2)

        # 3. Mode dark hits cache again
        preview_palette.preview(str(self.image), 'dark', 'req-3')
        self.assertEqual(self.subprocess_calls, 2)

        # 4. Same image path, modified content SHA256 (retaining old mtime) -> invalidates
        old_stat = self.image.stat()
        self.image.write_bytes(b'image-data-version-2-changed')
        os.utime(self.image, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
        preview_palette.preview(str(self.image), 'dark', 'req-4')
        self.assertEqual(self.subprocess_calls, 3, 'Changed image bytes must invalidate cache')

        # 5. Generator stat/binary identity changed -> invalidates
        self.binary.write_bytes(b'matugen-upgraded-binary-content')
        preview_palette.preview(str(self.image), 'dark', 'req-5')
        self.assertEqual(self.subprocess_calls, 4, 'Changed generator identity must invalidate cache')

    def test_corrupted_cache_recovery(self):
        # Initial run populates cache
        preview_palette.preview(str(self.image), 'dark', 'req-1')
        self.assertEqual(self.subprocess_calls, 1)

        cache_files = list((self.cache_dir / 'wallpaper-switcher/previews-v1').glob('*.json'))
        self.assertEqual(len(cache_files), 1)
        cache_file = cache_files[0]

        # Corrupt with non-JSON
        cache_file.write_text('{bad json syntax')
        resp = preview_palette.preview(str(self.image), 'dark', 'req-corrupt-1')
        self.assertEqual(self.subprocess_calls, 2, 'Malformed JSON cache must trigger regeneration')
        self.assertEqual(resp['swatches'], self.swatches_dark)

        # Corrupt with invalid swatches (not 5 colors)
        cache_file.write_text(json.dumps({'swatches': ['#112233']}))
        resp = preview_palette.preview(str(self.image), 'dark', 'req-corrupt-2')
        self.assertEqual(self.subprocess_calls, 3, 'Incomplete swatches must trigger regeneration')
        self.assertEqual(resp['swatches'], self.swatches_dark)

        # Corrupt with invalid color format
        cache_file.write_text(json.dumps({'swatches': ['red', '#223344', '#334455', '#445566', '#556677']}))
        resp = preview_palette.preview(str(self.image), 'dark', 'req-corrupt-3')
        self.assertEqual(self.subprocess_calls, 4, 'Invalid hex color swatches must trigger regeneration')
        self.assertEqual(resp['swatches'], self.swatches_dark)

    def test_cache_write_failure_fallback(self):
        # Make cache directory path unwritable (e.g. file exists where directory should be)
        preview_cache_dir = self.cache_dir / 'wallpaper-switcher' / 'previews-v1'
        preview_cache_dir.parent.mkdir(parents=True, exist_ok=True)
        preview_cache_dir.write_text('blocking-file-preventing-mkdir')

        resp = preview_palette.preview(str(self.image), 'dark', 'req-unwritable')
        self.assertEqual(self.subprocess_calls, 1)
        self.assertEqual(resp['swatches'], self.swatches_dark)
        self.assertEqual(resp['request_id'], 'req-unwritable')

    def test_non_object_or_wrong_schema_cache_regenerates(self):
        preview_palette.preview(str(self.image), 'dark', 'first')
        cache_file = next(self.cache_dir.rglob('*.json'))
        for bad in ['[]', 'null', json.dumps({'schema_version': 2, 'swatches': self.swatches_dark})]:
            with self.subTest(cache=bad):
                before = self.subprocess_calls
                cache_file.write_text(bad)
                result = preview_palette.preview(str(self.image), 'dark', 'retry')
                self.assertEqual(self.subprocess_calls, before + 1)
                self.assertEqual(result['swatches'], self.swatches_dark)

    def test_image_changed_during_generation_is_not_cached(self):
        def changing(cmd, **kwargs):
            result = self.fake_matugen_run(cmd, **kwargs)
            self.image.write_bytes(b'changed while Matugen ran')
            return result
        with patch.object(preview_palette.subprocess, 'run', side_effect=changing):
            preview_palette.preview(str(self.image), 'dark', 'racing-edit')
        self.assertEqual(list(self.cache_dir.rglob('*.json')), [])


if __name__ == '__main__':
    unittest.main()
