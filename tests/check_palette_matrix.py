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


def validate_rofi(path, env):
    args = ['rofi', '-no-config', '-rasi-validate', str(path)]
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
    if result.returncode == -11:
        # Shipped 2.0.0-dirty crashes in display_cleanup after this display-free CLI.
        # Skip only cleanup, preserving the parser's real exit status; no binary changes.
        run(['gdb', '-batch', '--return-child-result', '-iex', 'set debuginfod enabled off',
             '-ex', 'break display_cleanup', '-ex', 'run', '-ex', 'return', '-ex', 'continue',
             '--args', *args], env)
        return 'native-parser/gdb-cleanup-workaround'
    if result.returncode:
        raise RuntimeError(result.stderr or f'Rofi validation exited {result.returncode}')
    return 'native-parser'


def check(desktop=True):
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
        for app in ('hypr', 'rofi', 'noctalia/palettes', 'kitty', 'alacritty',
                    'gtk-3.0', 'gtk-4.0', 'qt6ct', 'btop'):
            (config / app).mkdir(parents=True, exist_ok=True)
        templates = []
        for name, source, output in [('hypr', 'hyprland-colors.conf', 'hypr/colors.conf'),
                                      ('rofi', 'rofi-colors.rasi', 'rofi/colors.rasi'),
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
                # Even the worst wallpaper under the 92%-opaque bar must remain readable.
                base = colors['mSurface'].lstrip('#')
                for wallpaper_channel in (0, 255):
                    mixed = '#' + ''.join(f'{round(int(base[i:i + 2], 16) * .92 + wallpaper_channel * .08):02x}'
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
                       'hl = {config=function(v) assert(v.general.col.active_border == c.primary) end}; '
                       'c.apply_theme()')
                run(['lua', '-e', lua], dict(env, RICE_TEST_ROOT=str(ROOT), RICE_TEST_PRIMARY=colors['mPrimary']))
                rofi = scratch / 'launcher.rasi'
                rofi.write_text((ROOT / 'config/rofi/config.rasi').read_text().replace(
                    '@import "colors.rasi"', f'@import "{config / "rofi/colors.rasi"}"'))
                parser_backend = validate_rofi(rofi, dict(os.environ, XDG_CONFIG_HOME=str(config))) if desktop else None
                report.append({'fixture': name, 'mode': mode, 'minimum_contrast': round(min(ratios), 2),
                               'native_templates_rendered': len(expected), 'rofi_parser_checked': desktop,
                               'rofi_parser_backend': parser_backend})
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-desktop', action='store_true', help='Render and check colors without the Rofi display-dependent parser')
    results = check(desktop=not parser.parse_args().no_desktop)
    if os.environ.get('RICE_MATRIX_REPORT'):
        Path(os.environ['RICE_MATRIX_REPORT']).write_text(json.dumps(results, indent=2) + '\n')
