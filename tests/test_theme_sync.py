"""Exercise theme transactions with desktop IPC replaced at the command boundary."""
import contextlib
import configparser
import hashlib
import importlib.util
import io
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'config/hypr/scripts/generate-theme.py'
spec = importlib.util.spec_from_file_location('theme_sync', SCRIPT)
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class ThemeSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.config, self.state, self.runtime = root / 'config', root / 'state', root / 'runtime'
        self.runtime.mkdir()
        self.wallpaper = root / 'wallpaper.png'
        self.wallpaper.write_bytes(b'image fixture')
        self.outputs = [self.config / p for p in ('hypr/colors.conf', 'micro/colorschemes/adaptive.micro',
                        'noctalia/palettes/matugen.json', 'kitty/themes/noctalia.conf')]
        for p in self.outputs:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('dark')
        (self.config / 'hypr/current_wallpaper').symlink_to(self.wallpaper)
        self.settings = self.state / 'noctalia/settings.toml'
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('mode = "light"\n')
        self.selected = str(self.wallpaper)
        self.mode = 'light'
        self.fail_templates = False
        self.backend_changes = []
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.config), 'XDG_STATE_HOME': str(self.state),
                                'XDG_DATA_HOME': str(root / 'data'),
                                'XDG_RUNTIME_DIR': str(self.runtime),
                                'NOCTALIA_WALLPAPER_PATH': str(self.wallpaper),
                                'HYPRLAND_INSTANCE_SIGNATURE': 'test-instance'}).start()
        patch.object(theme, 'command', side_effect=self.command).start()
        patch.object(theme, 'palette_for', side_effect=self.palette_for).start()
        patch.object(theme, 'stage_native', side_effect=self.stage_native).start()
        patch.object(theme, 'quiesce_shell', return_value=False).start()

    def command(self, argv):
        if argv[:3] == ['noctalia', 'config', 'export']:
            return f'[theme]\nmode = "{self.mode}"\nsource = "wallpaper"\nmatugen_palette = "matugen"\n'
        if argv[:2] == ['noctalia', 'msg']:
            if argv[2] == 'wallpaper-get': return self.selected
            if argv[2] == 'theme-mode-get': return self.mode
            if argv[2] == 'templates-apply':
                self.outputs[-1].write_text(self.mode)
                if self.fail_templates: raise RuntimeError('injected template failure')
            return ''
        if argv[0] in ('swww', 'awww', 'magick'):
            self.backend_changes.append(argv)
            raise AssertionError('Mode sync must not change wallpaper or thumbnail')
        if argv[0] == 'gsettings': return "'prefer-light'"
        if argv[0] == 'hyprctl': return ''
        raise AssertionError(f'Unexpected external command: {argv}')

    def palette_for(self, wallpaper, config):
        for p in self.outputs[:-1]: p.write_text(self.mode)
        return {}, {'theme': {'source': 'wallpaper', 'matugen_palette': 'matugen'}}, [], True, self.mode

    def stage_native(self, *args):
        return {str(self.outputs[-1]): hashlib.sha256(self.mode.encode()).hexdigest()}

    def run_mode_event(self):
        # Missing CLI support must fail as a result, not as a test import error.
        with patch('sys.argv', [str(SCRIPT), '--theme-mode-changed']), contextlib.redirect_stderr(io.StringIO()):
            try: return theme.main()
            except SystemExit as e: return e.code

    def test_mode_event_updates_outputs_and_preserves_wallpaper(self):
        self.assertEqual(self.run_mode_event(), 0)
        self.assertEqual([p.read_text() for p in self.outputs], ['light'] * len(self.outputs))
        self.assertEqual((self.config / 'hypr/current_wallpaper').resolve(), self.wallpaper)
        self.assertEqual(self.backend_changes, [])

    def test_mode_event_is_not_suppressed_by_a_wallpaper_transaction(self):
        request = {'wallpaper': str(self.wallpaper), 'mode': 'dark', 'expires': theme.time.time() + 45,
                   'palette': hashlib.sha256(self.outputs[-2].read_bytes()).hexdigest()}
        (self.runtime / 'noctalia-matugen-request.json').write_text(json.dumps(request))
        self.assertEqual(self.run_mode_event(), 0)
        self.assertEqual(self.outputs[-1].read_text(), 'light')

    def test_wallpaper_request_in_another_mode_does_not_skip_sync(self):
        request = {'wallpaper': str(self.wallpaper), 'mode': 'dark', 'expires': theme.time.time() + 45,
                   'palette': hashlib.sha256(self.outputs[-2].read_bytes()).hexdigest()}
        (self.runtime / 'noctalia-matugen-request.json').write_text(json.dumps(request))
        theme.wallpaper_changed(self.config, self.state, self.runtime)
        self.assertEqual(self.outputs[-1].read_text(), 'light')

    def test_repeated_mode_switches_leave_the_latest_palette(self):
        for mode in ['light', 'dark', 'light']:
            self.mode = mode
            self.assertEqual(self.run_mode_event(), 0)
            self.assertEqual([p.read_text() for p in self.outputs], [mode] * len(self.outputs))

    def test_mode_event_updates_gtk_preferences_without_losing_user_settings(self):
        gtk3 = self.config / 'gtk-3.0/settings.ini'
        gtk3.parent.mkdir()
        gtk3.write_text('[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-application-prefer-dark-theme=1\ngtk-cursor-theme-size=24\n')
        (self.config / 'gtk-4.0').mkdir()
        self.assertEqual(self.run_mode_event(), 0)
        ini = configparser.ConfigParser()
        ini.read(gtk3)
        self.assertEqual(ini['Settings']['gtk-application-prefer-dark-theme'], '0')
        self.assertEqual(ini['Settings']['gtk-theme-name'], 'adw-gtk3')
        self.assertEqual(ini['Settings']['gtk-cursor-theme-size'], '24')
        ini.read(self.config / 'gtk-4.0/settings.ini')
        self.assertEqual(ini['Settings']['gtk-icon-theme-name'], 'Papirus')

    def test_failed_mode_event_restores_files_without_reverting_user_mode(self):
        self.fail_templates = True
        self.assertEqual(self.run_mode_event(), 1)
        self.assertEqual([p.read_text() for p in self.outputs], ['dark'] * len(self.outputs))
        self.assertEqual(self.settings.read_text(), 'mode = "light"\n')

    def test_failed_event_removes_a_new_micro_colorscheme(self):
        micro = self.config / 'micro/colorschemes/adaptive.micro'
        micro.unlink()
        self.fail_templates = True
        self.assertEqual(self.run_mode_event(), 1)
        self.assertFalse(micro.exists())

    def test_wallpaper_rollback_preserves_a_newer_user_mode(self):
        self.mode = 'dark'
        self.settings.write_text('mode = "dark"\n')
        original = self.command
        def command(argv):
            if argv[0] == 'swww': return ''
            return original(argv)
        def change_mode(*args):
            self.mode = 'light'
            self.settings.write_text('mode = "light"\n')
            raise RuntimeError('newer mode selected')
        with patch.object(theme, 'command', side_effect=command), \
             patch.object(theme, 'wait_for_templates', side_effect=change_mode), \
             patch.object(theme.time, 'sleep'):
            with self.assertRaises(RuntimeError):
                theme.apply(self.wallpaper, self.config, self.state, self.runtime)
        self.assertEqual(self.settings.read_text(), 'mode = "light"\n')

    def test_queued_old_wallpaper_event_leaves_outputs_untouched(self):
        self.selected = str(self.wallpaper.parent / 'newer.png')
        Path(self.selected).write_bytes(b'new selection')
        theme.wallpaper_changed(self.config, self.state, self.runtime)
        self.assertEqual([p.read_text() for p in self.outputs], ['dark'] * len(self.outputs))

    def test_missing_wallpaper_does_not_write_theme_files(self):
        self.wallpaper.unlink()
        self.assertEqual(self.run_mode_event(), 1)
        self.assertEqual([p.read_text() for p in self.outputs], ['dark'] * len(self.outputs))

    def test_rollback_handles_a_shell_that_has_already_exited(self):
        original = self.command
        cause = subprocess.CalledProcessError(1, ['pgrep'])
        error = RuntimeError('Command failed with exit code 1')
        error.__cause__ = cause
        def command(argv):
            if argv[0] == 'pgrep': raise error
            return original(argv)
        real_spec = importlib.util.spec_from_file_location('real_theme_sync', SCRIPT)
        real = importlib.util.module_from_spec(real_spec)
        real_spec.loader.exec_module(real)
        with patch.object(real, 'command', side_effect=command):
            self.assertFalse(real.quiesce_shell())


if __name__ == '__main__':
    unittest.main()
