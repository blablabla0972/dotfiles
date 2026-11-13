"""Cached rendering must skip Matugen without restoring stale or damaged outputs."""
import configparser
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
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

    def test_aba_input_replacement_does_not_poison_cache(self):
        for path in (self.image, self.template, self.source):
            with self.subTest(path=path.name):
                for record in self.cache.rglob('*.json'):
                    record.unlink()
                original = path.read_bytes()
                previous_records = set(self.cache.rglob('*.json'))
                previous_calls = self.calls

                def replace_and_restore(argv):
                    stamp = path.stat()
                    path.write_bytes(original + b'changed during rendering')
                    self.generate(argv)
                    for name in theme.MATUGEN_OUTPUTS:
                        (self.config / name).write_bytes(b'palette for ' + path.read_bytes())
                    path.write_bytes(original)
                    os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))

                with patch.object(theme, 'command', side_effect=replace_and_restore):
                    self.render()
                self.assertEqual(path.read_bytes(), original)
                self.assertEqual(set(self.cache.rglob('*.json')), previous_records)
                self.render()
                self.assertEqual(self.calls, previous_calls + 2)
                for name in theme.MATUGEN_OUTPUTS:
                    self.assertEqual((self.config / name).read_bytes(),
                                     f'{name}: render {self.calls}\r\n'.encode())
                self.render()
                self.assertEqual(self.calls, previous_calls + 2, 'Stable inputs must still hit cache')

    def test_template_alias_retarget_does_not_change_the_hashed_render_input(self):
        original_config = self.source.read_text()
        for kind in ('file', 'directory'):
            with self.subTest(kind=kind):
                for record in self.cache.rglob('*.json'):
                    record.unlink()
                first, second = self.root / (kind + '-A'), self.root / (kind + '-B')
                first.mkdir()
                second.mkdir()
                (first / 'template').write_bytes(b'palette-A')
                (second / 'template').write_bytes(b'palette-B')
                targets = (first, second) if kind == 'directory' else (first / 'template', second / 'template')
                alias = self.config / 'matugen' / (kind + '-alias')
                alias.symlink_to(targets[0], target_is_directory=kind == 'directory')
                input_path = alias / 'template' if kind == 'directory' else alias
                self.source.write_text(original_config.replace(str(self.template), str(input_path)))
                previous_calls = self.calls

                def retarget_during_render(argv):
                    self.calls += 1
                    alias.unlink()
                    alias.symlink_to(targets[1], target_is_directory=kind == 'directory')
                    rendered_config = tomllib.loads(Path(argv[argv.index('--config') + 1]).read_text())
                    template = Path(next(iter(rendered_config['templates'].values()))['input_path'])
                    for name in theme.MATUGEN_OUTPUTS:
                        output = self.config / name
                        output.parent.mkdir(parents=True, exist_ok=True)
                        output.write_bytes(template.read_bytes())
                    alias.unlink()
                    alias.symlink_to(targets[0], target_is_directory=kind == 'directory')

                with patch.object(theme, 'command', side_effect=retarget_during_render):
                    self.render()
                    self.assertEqual({(self.config / name).read_bytes() for name in theme.MATUGEN_OUTPUTS},
                                     {b'palette-A'})
                    self.render()
                self.assertEqual(self.calls, previous_calls + 1, 'Stable resolved inputs must hit cache')
                self.assertEqual(alias.resolve(), targets[0])


@unittest.skipUnless(shutil.which('matugen'), 'Matugen is required for client template rendering')
class MatugenClientTemplatesTest(unittest.TestCase):
    def test_quickshell_clients_render_and_noctalia_skips_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'config'
            shutil.copytree(ROOT / 'config/matugen', config / 'matugen')
            image = root / 'wallpaper.png'
            image.write_bytes(b'cache fixture; Matugen receives a hex source')

            def run_matugen(argv):
                config_arg = argv[argv.index('--config') + 1]
                mode = argv[argv.index('--mode') + 1]
                result = subprocess.run(
                    ['matugen', 'color', 'hex', '#4675ac', '--config', config_arg, '--mode', mode, '--quiet'],
                    capture_output=True, text=True, check=True)
                return result.stdout

            with patch.dict(os.environ, XDG_CACHE_HOME=str(root / 'cache')), \
                 patch.object(theme, 'command', side_effect=run_matugen):
                theme.render_matugen(image, config, 'dark', backend='quickshell')
                results = {name: (config / name).read_text()
                           for name in theme.MATUGEN_QUICKSHELL_OUTPUTS}
                self.assertTrue(all('{{' not in value for value in results.values()))
                alacritty = tomllib.loads(results['alacritty/themes/noctalia.toml'])
                self.assertTrue(alacritty['colors']['normal']['red'].startswith('#'))
                self.assertIn('color15 #', results['kitty/themes/noctalia.conf'])
                self.assertIn('@define-color window_bg_color #', results['gtk-3.0/gtk.css'])
                self.assertEqual(results['gtk-3.0/gtk.css'], results['gtk-4.0/gtk.css'])
                self.assertIn('theme[main_bg]="#', results['btop/themes/noctalia.theme'])
                self.assertIn('theme[proc_start]="#', results['btop/themes/noctalia.theme'])
                for app in ('qt5ct', 'qt6ct'):
                    palette = configparser.ConfigParser()
                    palette.read_string(results[f'{app}/colors/noctalia.conf'])
                    for state in ('active_colors', 'disabled_colors', 'inactive_colors'):
                        colors = palette['ColorScheme'][state].split(',')
                        self.assertEqual(len(colors), 21)
                        self.assertTrue(all(color.strip().startswith('#') for color in colors))

                theme.render_matugen(image, config, 'light', backend='quickshell')
                lighter = {name: (config / name).read_text() for name in results}
                self.assertNotEqual(lighter['kitty/themes/noctalia.conf'],
                                    results['kitty/themes/noctalia.conf'])

                # Switching back to Noctalia must not overwrite its native client themes.
                theme.render_matugen(image, config, 'dark', backend='noctalia')
                self.assertEqual({name: (config / name).read_text() for name in results}, lighter)

    def test_client_outputs_are_snapshot_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, state = root / 'config', root / 'state'
            existing = config / theme.MATUGEN_QUICKSHELL_OUTPUTS[0]
            new = config / theme.MATUGEN_QUICKSHELL_OUTPUTS[-1]
            existing.parent.mkdir(parents=True)
            existing.write_text('original')
            snapshot = theme.Snapshot(theme.theme_snapshot_paths(config, state), state)
            existing.write_text('overwritten')
            new.parent.mkdir(parents=True)
            new.write_text('new theme')
            snapshot.restore()
            self.assertEqual(existing.read_text(), 'original')
            self.assertFalse(new.exists())

    def test_quickshell_activates_qt_palettes_without_losing_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            for app in ('qt5ct', 'qt6ct'):
                path = config / app / f'{app}.conf'
                path.parent.mkdir(parents=True)
                path.write_text('[Appearance]\nstyle=Fusion\n')
            with patch.object(theme, 'detect_backend', return_value='quickshell'):
                theme.sync_toolkit_settings(config, 'dark')
            for app in ('qt5ct', 'qt6ct'):
                ini = configparser.ConfigParser()
                ini.read(config / app / f'{app}.conf')
                appearance = ini['Appearance']
                self.assertEqual(appearance['style'], 'Fusion')
                self.assertEqual(appearance['custom_palette'], 'true')
                self.assertEqual(appearance['color_scheme_path'], str(config / app / 'colors/noctalia.conf'))


if __name__ == '__main__':
    unittest.main()
