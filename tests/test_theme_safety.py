"""Exercise Matugen isolation and rollback with real rendering in a temporary HOME."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'config/hypr/scripts/generate-theme.py'
spec = importlib.util.spec_from_file_location('theme_safety', SCRIPT)
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class SnapshotSafetyTest(unittest.TestCase):
    def test_restore_preserves_symlink_and_target_contents_and_mode(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(theme.shutil, 'which', return_value=None):
            root = Path(directory)
            target = root / 'original.conf'
            target.write_bytes(b'ORIGINAL')
            target.chmod(0o640)
            link = root / 'theme.conf'
            link.symlink_to(target.name)
            snap = theme.Snapshot([link], root / 'state')
            link.write_bytes(b'CHANGED THROUGH LINK')
            target.chmod(0o600)
            link.unlink()
            link.write_bytes(b'REPLACED LINK')
            snap.restore()
            self.assertTrue(link.is_symlink())
            self.assertEqual(os.readlink(link), target.name)
            self.assertEqual(target.read_bytes(), b'ORIGINAL')
            self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_restore_removes_new_referent_of_a_preexisting_dangling_link(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(theme.shutil, 'which', return_value=None):
            root = Path(directory)
            target = root / 'missing.conf'
            link = root / 'theme.conf'
            link.symlink_to(target.name)
            snap = theme.Snapshot([link], root / 'state')
            link.write_bytes(b'NEW CONTENT')
            snap.restore()
            self.assertTrue(link.is_symlink())
            self.assertFalse(target.exists())


@unittest.skipUnless(all(shutil.which(name) for name in ('matugen', 'magick', 'noctalia')),
                     'Real Matugen, ImageMagick and Noctalia are required')
class MatugenSafetyTest(unittest.TestCase):
    outputs = ('hypr/colors.conf', 'noctalia/palettes/matugen.json', 'micro/colorschemes/adaptive.micro')

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / 'space "Ảnh"'
        self.home = self.root / 'home'
        self.home_config = self.home / '.config'
        self.config = self.root / 'xdg-config'
        for config in (self.home_config, self.config):
            shutil.copytree(ROOT / 'config/matugen', config / 'matugen')
        self.image = self.root / 'wallpaper.png'
        subprocess.run(['magick', '-size', '8x8', 'gradient:#14263e-#77a6ca', str(self.image)],
                       check=True, capture_output=True)
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                   XDG_STATE_HOME=str(self.root / 'state'), XDG_DATA_HOME=str(self.root / 'data'),
                   XDG_RUNTIME_DIR=str(self.root / 'runtime'))
        for key in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS'):
            env.pop(key, None)
        self.env_patch = patch.dict(os.environ, env, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.real_command = theme.command
        self.fail_resolver = False
        command_patch = patch.object(theme, 'command', side_effect=self.command)
        command_patch.start()
        self.addCleanup(command_patch.stop)

    def command(self, argv):
        if argv[0] == 'gsettings': return "'dark'" if argv[1] == 'get' else ''
        if argv[:3] == ['noctalia', 'config', 'export']:
            return '[theme]\nmode="dark"\nsource="wallpaper"\nmatugen_palette="matugen"\n'
        if argv[:2] == ['noctalia', 'msg']: return ''  # Never contact the desktop.
        if self.fail_resolver and argv[:2] == ['noctalia', 'theme']:
            raise RuntimeError('injected resolver failure')
        return self.real_command(argv)

    def write_sentinels(self, config):
        for relative in self.outputs:
            path = config / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'PRESERVE')

    def test_xdg_render_does_not_touch_default_home_outputs(self):
        self.write_sentinels(self.home_config)
        theme.palette_for(self.image, self.config)
        for relative in self.outputs:
            self.assertTrue((self.config / relative).is_file(), relative)
            self.assertEqual((self.home_config / relative).read_bytes(), b'PRESERVE')

    def test_xdg_render_with_symlinked_matugen_directory(self):
        self.write_sentinels(self.home_config)
        shutil.rmtree(self.config / 'matugen')
        (self.config / 'matugen').symlink_to(self.home_config / 'matugen', target_is_directory=True)
        theme.palette_for(self.image, self.config)
        for relative in self.outputs:
            self.assertTrue((self.config / relative).is_file(), relative)
            self.assertEqual((self.home_config / relative).read_bytes(), b'PRESERVE')

    def test_relative_template_paths_stay_under_xdg_config(self):
        self.write_sentinels(self.home_config)
        config_file = self.config / 'matugen/config.toml'
        config_file.write_text(config_file.read_text().replace('~/.config/matugen/templates/', 'templates/')
                               .replace('~/.config/', '../'))
        theme.palette_for(self.image, self.config)
        for relative in self.outputs:
            self.assertTrue((self.config / relative).is_file(), relative)
            self.assertEqual((self.home_config / relative).read_bytes(), b'PRESERVE')

    def test_unprotected_output_is_rejected_before_matugen_writes(self):
        config_file = self.config / 'matugen/config.toml'
        outside = self.root / 'unprotected.conf'
        outside.write_bytes(b'PRESERVE')
        config_file.write_text(config_file.read_text().replace('~/.config/hypr/colors.conf', str(outside)))
        with self.assertRaisesRegex(RuntimeError, 'backup paths'):
            theme.palette_for(self.image, self.config)
        self.assertEqual(outside.read_bytes(), b'PRESERVE')
        self.assertFalse((self.config / 'noctalia/palettes/matugen.json').exists())

    def test_plain_regeneration_rolls_back_existing_and_new_micro_output(self):
        self.config = self.home_config
        self.fail_resolver = True
        with patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config)):
            for existing in (True, False):
                with self.subTest(existing_micro=existing):
                    self.write_sentinels(self.config)
                    micro = self.config / self.outputs[-1]
                    if not existing: micro.unlink()
                    with patch('sys.argv', [str(SCRIPT), str(self.image)]), contextlib.redirect_stderr(io.StringIO()):
                        self.assertEqual(theme.main(), 1)
                    self.assertEqual(micro.read_bytes() if existing else micro.exists(), b'PRESERVE' if existing else False)
                    for relative in self.outputs[:-1]:
                        self.assertEqual((self.config / relative).read_bytes(), b'PRESERVE')


if __name__ == '__main__':
    unittest.main()
