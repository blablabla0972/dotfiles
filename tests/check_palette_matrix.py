"""Render real Matugen/Noctalia templates in isolation; print only failures."""
import configparser
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme_sync', ROOT / 'config/hypr/scripts/generate-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


def run(args, env):
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise RuntimeError(f'{args[0]} exited {result.returncode}: {result.stderr[-1500:]}')
    return result.stdout


def luminance(color):
    channels = [int(color.lstrip('#')[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return sum(weight * (c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4)
               for weight, c in zip((.2126, .7152, .0722), channels))


def contrast(foreground, background):
    values = sorted((luminance(foreground), luminance(background)))
    return (values[1] + .05) / (values[0] + .05)


def check(desktop=True):
    hyprland = (ROOT / 'config/hypr/hyprland.lua').read_text()
    assert hyprland.count('require("noctalia").apply_theme()') == 1
    assert 'require("config.colors").apply_theme()' not in hyprland
    bar_alpha = tomllib.loads((ROOT / 'config/noctalia/config.toml').read_text())['bar']['default']['background_opacity']
    pairs = [('mOnSurface', 'mSurface'), ('mOnSurfaceVariant', 'mSurfaceVariant'),
             ('mOnPrimary', 'mPrimary'), ('mOnSecondary', 'mSecondary'),
             ('mOnError', 'mError'), ('mOnHover', 'mHover')]
    fixtures = [('cool', '#14263e', '#77a6ca'), ('warm', '#382019', '#c29a6a'),
                ('green', '#142c22', '#83ad81'), ('muted', '#292a2c', '#a0a1a3'),
                ('bright', '#f6efdc', '#c9dfea'), ('busy', '#26203a', '#d79b79')]
    report = []
    with tempfile.TemporaryDirectory(prefix='adaptive-palette-') as directory:
        scratch = Path(directory)
        config, data = scratch / 'config', scratch / 'data'
        env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                   XDG_STATE_HOME=str(scratch / 'state'), XDG_RUNTIME_DIR=str(scratch / 'runtime'))
        for name in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS'):
            env.pop(name, None)
        for app in ('hypr', 'noctalia/palettes', 'kitty', 'alacritty',
                    'gtk-3.0', 'gtk-4.0', 'qt6ct', 'btop'):
            (config / app).mkdir(parents=True, exist_ok=True)
        templates = []
        for name, source, output in [('hypr', 'hyprland-colors.conf', 'hypr/colors.conf'),
                                      ('noctalia', 'noctalia-palette.json', 'noctalia/palettes/matugen.json')]:
            templates.append(f'[templates.{name}]\ninput_path = {json.dumps(str(ROOT / "config/matugen/templates" / source))}\noutput_path = {json.dumps(str(config / output))}\n')
        matugen_config = scratch / 'matugen.toml'
        matugen_config.write_text('[config.wallpaper]\ncommand = "true"\narguments = []\nset = false\n' + '\n'.join(templates))
        catalog = {'theme': {'templates': {'builtin_ids': ['hyprland', 'kitty', 'gtk3', 'gtk4',
                                                         'qt', 'kcolorscheme', 'alacritty', 'btop']}}}
        for name, low, high in fixtures:
            image = scratch / f'{name}.png'
            args = ['magick', '-size', '480x270', f'gradient:{low}-{high}']
            if name == 'busy': args += ['-wave', '20x35', '-swirl', '90']
            run(args + [str(image)], env)
            for mode in ('dark', 'light'):
                run(['matugen', 'image', str(image), '--config', str(matugen_config), '--mode', mode,
                     '--prefer', 'less-saturation', '--source-color-index', '0', '--quiet'], env)
                palette_path = config / 'noctalia/palettes/matugen.json'
                colors = json.loads(palette_path.read_text())[mode]
                ratios = [contrast(colors[fg], colors[bg]) for fg, bg in pairs]
                terminal = colors['terminal']
                ratios += [contrast(terminal['foreground'], terminal['background']),
                           contrast(terminal['selectionFg'], terminal['selectionBg'])]
                # Check the actual bar opacity against white/black wallpaper.
                base = colors['mSurface'].lstrip('#')
                for alpha in (bar_alpha,):
                    for wallpaper_channel in (0, 255):
                        mixed = '#' + ''.join(f'{round(int(base[i:i + 2], 16) * alpha + wallpaper_channel * (1-alpha)):02x}'
                                              for i in (0, 2, 4))
                        ratios.append(contrast(colors['mOnSurface'], mixed))
                assert min(ratios) >= 4.5, (name, mode, min(ratios))
                native_command = ['noctalia', 'theme', str(image), '--theme-json', str(palette_path),
                                  '--both', '--default-mode', mode]
                native = json.loads(run(native_command, env))
                assert native[mode]['primary'] == colors['mPrimary']
                rendered = scratch / f'{name}-{mode}'
                rendered.mkdir()
                expected = theme.stage_native(native_command, catalog, config, data, rendered)
                # stage_native renders only into scratch and must never deploy or execute hooks.
                assert not (config / 'kitty/themes/noctalia.conf').exists()
                staged = {target: rendered / f'expected-{i}' for i, target in enumerate(expected)}
                for target, path in staged.items():
                    if target.endswith('.lua'): run(['luac', '-p', str(path)], env)
                    if target.endswith('.toml'): tomllib.loads(path.read_text())
                    if target.endswith('/noctalia.conf') and '/qt6ct/' in target:
                        ini = configparser.ConfigParser(); ini.read(path)
                        assert len(ini['ColorScheme']['active_colors'].split(',')) == 22
                    if target.endswith('.css'):
                        import gi
                        gi.require_version('Gtk', '4.0')
                        from gi.repository import Gtk
                        errors = []
                        provider = Gtk.CssProvider()
                        provider.connect('parsing-error', lambda _, section, error: errors.append(str(error)))
                        provider.load_from_path(str(path))
                        assert not errors, (target, errors)
                lua = ('package.path = os.getenv("RICE_TEST_ROOT") .. "/config/hypr/?.lua;" .. package.path; '
                       'local c = require("config.colors"); '
                       'assert(c.primary == "rgba(" .. os.getenv("RICE_TEST_PRIMARY"):sub(2) .. "ff)"); '
                       'assert(c.apply_theme == nil); '
                       'local function same(actual, name) local expected = "rgb(" .. os.getenv(name):sub(2) .. ")"; '
                       'assert(actual == expected, tostring(actual) .. " != " .. expected) end; '
                       'local calls = 0; '
                       'hl = {config=function(v) calls = calls + 1; '
                       'same(v.general.col.active_border, "RICE_TEST_PRIMARY"); '
                       'same(v.general.col.inactive_border, "RICE_TEST_SURFACE"); '
                       'same(v.group.col.border_active, "RICE_TEST_SECONDARY"); '
                       'same(v.group.col.border_inactive, "RICE_TEST_SURFACE"); '
                       'same(v.group.col.border_locked_active, "RICE_TEST_ERROR"); '
                       'same(v.group.col.border_locked_inactive, "RICE_TEST_SURFACE"); '
                       'same(v.group.groupbar.col.active, "RICE_TEST_SECONDARY"); '
                       'same(v.group.groupbar.col.inactive, "RICE_TEST_SURFACE"); '
                       'same(v.group.groupbar.col.locked_active, "RICE_TEST_ERROR"); '
                       'same(v.group.groupbar.col.locked_inactive, "RICE_TEST_SURFACE"); '
                       'same(v.group.groupbar.text_color, "RICE_TEST_ON_SECONDARY"); '
                       'same(v.group.groupbar.text_color_inactive, "RICE_TEST_ON_SURFACE"); '
                       'same(v.group.groupbar.text_color_locked_active, "RICE_TEST_ON_ERROR"); '
                       'same(v.group.groupbar.text_color_locked_inactive, "RICE_TEST_ON_SURFACE") end}; '
                       'dofile(os.getenv("RICE_TEST_NOCTALIA")).apply_theme(); '
                       'assert(calls == 1)')
                run(['lua', '-e', lua], dict(env, RICE_TEST_ROOT=str(ROOT),
                                              RICE_TEST_PRIMARY=native[mode]['primary'],
                                              RICE_TEST_SURFACE=native[mode]['surface'],
                                              RICE_TEST_SECONDARY=native[mode]['secondary'],
                                              RICE_TEST_ERROR=native[mode]['error'],
                                              RICE_TEST_ON_SECONDARY=native[mode]['on_secondary'],
                                              RICE_TEST_ON_SURFACE=native[mode]['on_surface'],
                                              RICE_TEST_ON_ERROR=native[mode]['on_error'],
                                              RICE_TEST_NOCTALIA=staged[str(config / 'hypr/noctalia.lua')]))
                report.append({'fixture': name, 'mode': mode, 'minimum_contrast': round(min(ratios), 2),
                               'native_templates_rendered': len(expected)})
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-desktop', action='store_true', help='Compatibility flag; validation runs without a display')
    results = check(desktop=not parser.parse_args().no_desktop)
    if os.environ.get('RICE_MATRIX_REPORT'):
        Path(os.environ['RICE_MATRIX_REPORT']).write_text(json.dumps(results, indent=2) + '\n')
