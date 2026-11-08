import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WorktreePathTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wt-prep-paths-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / 'source'
        self.hypr = self.source / 'config/hypr'
        self.hypr.mkdir(parents=True)
        self.destination = self.source / '.worktrees/preview'
        self.target = self.destination / 'config/hypr'
        self.target.mkdir(parents=True)
        self.script = self.source / 'wt-prep.sh'
        shutil.copy2(Path(__file__).resolve().parents[1] / 'wt-prep.sh', self.script)

    def prepare(self):
        return subprocess.run(
            ['bash', str(self.script), str(self.destination)],
            capture_output=True, text=True,
            env={**os.environ, 'HOME': str(self.base / 'home')},
        )

    def test_gpu_alias_rejected_before_wallpaper_changes(self):
        (self.hypr / 'current_wallpaper').write_text('NEW')
        (self.target / 'current_wallpaper').write_text('OLD')
        (self.target / 'gpu').mkdir()
        (self.target / 'gpu/intel').write_text('ONLY_GPU_INPUT')
        (self.hypr / 'gpu').symlink_to(self.target / 'gpu', target_is_directory=True)
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.target / 'current_wallpaper').read_text(), 'OLD')
        self.assertEqual((self.hypr / 'gpu/intel').read_text(), 'ONLY_GPU_INPUT')
        self.assertFalse((self.target / 'gpu').is_symlink())

    def test_relative_wallpaper_preserves_original_referent(self):
        image = self.base / 'wallpaper.png'
        image.write_bytes(b'IMAGE')
        (self.hypr / 'current_wallpaper').symlink_to('../../../wallpaper.png')
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        copied = self.target / 'current_wallpaper'
        self.assertTrue(copied.is_symlink())
        self.assertEqual(copied.resolve(), image)
        self.assertEqual(copied.read_bytes(), b'IMAGE')

    def test_wallpaper_intermediate_link_in_removed_gpu_is_rejected(self):
        image = self.base / 'external.png'
        image.write_bytes(b'IMAGE')
        (self.target / 'gpu').mkdir()
        intermediate = self.target / 'gpu/image-link'
        intermediate.symlink_to(image)
        wallpaper = self.hypr / 'current_wallpaper'
        wallpaper.symlink_to(intermediate)
        (self.hypr / 'gpu').mkdir()
        (self.target / 'current_wallpaper').write_text('OLD')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.target / 'current_wallpaper').read_text(), 'OLD')
        self.assertEqual(wallpaper.read_bytes(), b'IMAGE')
        self.assertEqual(os.readlink(intermediate), str(image))

    def check_parent_hop_rejected(self, name):
        shared = self.base / 'shared'
        shared.mkdir()
        (shared / 'payload').write_text('PAYLOAD')
        (self.target / 'gpu').mkdir()
        (self.target / 'gpu/bridge').symlink_to(shared, target_is_directory=True)
        router = self.base / 'router'
        router.symlink_to(self.target / 'gpu/bridge', target_is_directory=True)
        (self.hypr / 'gpu').mkdir()
        link = self.hypr / name
        link.symlink_to(router / 'payload')
        if name != 'current_wallpaper':
            (self.hypr / 'current_wallpaper').write_text('NEW')
        (self.target / 'current_wallpaper').write_text('OLD')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.target / 'current_wallpaper').read_text(), 'OLD')
        self.assertEqual(link.read_text(), 'PAYLOAD')
        self.assertTrue((self.target / 'gpu/bridge').is_symlink())

    def test_source_file_parent_hops_are_rejected(self):
        self.check_parent_hop_rejected('current_wallpaper')

    def test_gpu_inner_parent_hops_are_rejected(self):
        self.check_parent_hop_rejected('gpu/intel')

    def test_safe_chains_and_dangling_gpu_chains_remain_supported(self):
        image = self.base / 'external.png'
        image.write_bytes(b'IMAGE')
        alias = self.base / 'image-alias'
        alias.symlink_to(image)
        (self.hypr / 'current_wallpaper').symlink_to(alias)
        (self.hypr / 'gpu').mkdir()
        devices = self.base / 'devices'
        devices.symlink_to(self.base / 'missing-devices', target_is_directory=True)
        (self.hypr / 'gpu/intel').symlink_to(os.path.relpath(devices / 'intel', self.hypr / 'gpu'))
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.target / 'current_wallpaper').is_symlink())
        self.assertEqual((self.target / 'current_wallpaper').read_bytes(), b'IMAGE')
        self.assertTrue((self.target / 'gpu/intel').is_symlink())
        self.assertEqual((self.target / 'gpu/intel').resolve(), self.base / 'missing-devices/intel')

    def test_removed_ancestor_before_dotdot_is_rejected(self):
        (self.hypr / 'gpu').mkdir()
        (self.target / 'gpu').mkdir()
        image = self.target / 'external.png'
        image.write_bytes(b'IMAGE')
        wallpaper = self.hypr / 'current_wallpaper'
        wallpaper.symlink_to(str(self.target / 'gpu') + '/../external.png')
        (self.target / 'current_wallpaper').write_text('OLD')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.target / 'current_wallpaper').read_text(), 'OLD')
        self.assertEqual(wallpaper.read_bytes(), b'IMAGE')
        self.assertTrue((self.target / 'gpu').is_dir())

    def test_symlink_hop_limit_before_destination_mutation(self):
        image = self.base / 'external.png'
        image.write_bytes(b'IMAGE')
        wallpaper = self.hypr / 'current_wallpaper'
        destination = self.target / 'current_wallpaper'
        for hops in (40, 41):
            with self.subTest(hops=hops):
                if wallpaper.is_symlink():
                    wallpaper.unlink()
                if destination.is_symlink():
                    destination.unlink()
                destination.write_text('OLD')
                target = image
                for index in range(hops - 1):
                    link = self.base / f'chain-{hops}-{index}'
                    link.symlink_to(target)
                    target = link
                wallpaper.symlink_to(target)
                result = self.prepare()
                if hops == 40:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(destination.is_symlink())
                    self.assertEqual(destination.read_bytes(), b'IMAGE')
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('too many symlink hops', result.stderr)
                    self.assertEqual(destination.read_text(), 'OLD')

    def test_wallpaper_referent_in_destination_gpu_is_preserved(self):
        (self.target / 'gpu').mkdir()
        payload = self.target / 'gpu/wallpaper.png'
        payload.write_bytes(b'ONLY_IMAGE')
        (self.hypr / 'current_wallpaper').symlink_to(payload)
        (self.hypr / 'gpu').mkdir()
        (self.target / 'current_wallpaper').write_text('OLD')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload.read_bytes(), b'ONLY_IMAGE')
        self.assertEqual((self.target / 'current_wallpaper').read_text(), 'OLD')

    def test_inner_gpu_alias_rejected_before_wallpaper_changes(self):
        (self.hypr / 'gpu').mkdir()
        (self.hypr / 'current_wallpaper').write_text('NEW')
        old = self.target / 'current_wallpaper'
        old.write_text('ONLY_GPU_INPUT')
        (self.hypr / 'gpu/intel').symlink_to(old)
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(old.read_text(), 'ONLY_GPU_INPUT')

    def test_shared_absolute_wallpaper_links_are_safe_to_replace(self):
        image = self.base / 'wallpaper.png'
        image.write_bytes(b'IMAGE')
        for parent in (self.hypr, self.target):
            (parent / 'current_wallpaper').symlink_to(image)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / 'current_wallpaper').read_bytes(), b'IMAGE')

    def test_relative_gpu_root_preserves_existing_and_dangling_targets(self):
        for exists in (True, False):
            with self.subTest(exists=exists):
                shared = self.base / ('gpu-existing' if exists else 'gpu-missing')
                if exists:
                    shared.mkdir()
                    (shared / 'intel').symlink_to('/dev/dri/intentionally-missing')
                source = self.hypr / 'gpu'
                if source.is_symlink():
                    source.unlink()
                source.symlink_to(os.path.relpath(shared, self.hypr), target_is_directory=True)
                result = self.prepare()
                self.assertEqual(result.returncode, 0, result.stderr)
                copied = self.target / 'gpu'
                self.assertTrue(copied.is_symlink())
                self.assertEqual(copied.resolve(), shared)
                if exists:
                    self.assertEqual(os.readlink(shared / 'intel'), '/dev/dri/intentionally-missing')

    def test_relative_inner_gpu_links_preserve_original_referents(self):
        gpu = self.hypr / 'gpu'
        (gpu / 'nested').mkdir(parents=True)
        shared = self.base / 'gpu-targets'
        shared.mkdir()
        (shared / 'intel').write_text('DEVICE_FIXTURE')
        (shared / 'untouched').symlink_to('../intentionally-missing')
        for name in ('intel', 'missing'):
            link = gpu / 'nested' / name
            link.symlink_to(os.path.relpath(shared / name, link.parent))
        (gpu / 'directory').symlink_to(os.path.relpath(shared, gpu), target_is_directory=True)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('intel', 'missing'):
            copied = self.target / 'gpu/nested' / name
            self.assertTrue(copied.is_symlink())
            self.assertEqual(copied.resolve(), shared / name)
        self.assertEqual((self.target / 'gpu/nested/intel').read_text(), 'DEVICE_FIXTURE')
        self.assertEqual((self.target / 'gpu/directory').resolve(), shared)
        self.assertTrue((self.target / 'gpu/directory').is_symlink())
        self.assertEqual(os.readlink(shared / 'untouched'), '../intentionally-missing')
        self.assertFalse((self.target / 'gpu/nested/missing').exists())


if __name__ == '__main__':
    unittest.main()
