"""Render real Matugen/Noctalia templates in isolation; print only failures."""
import configparser
import argparse
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import tomllib
from unittest import TestCase
from unittest.mock import patch


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


def composite(foreground, background, alpha):
    return '#' + ''.join(f'{round(int(foreground[i:i + 2], 16) * alpha + int(background[i:i + 2], 16) * (1 - alpha)):02x}'
                         for i in (1, 3, 5))


def bar_contrast_samples(palette, config):
    """Measure visible text against its capsule, including group overrides."""
    bar = config['bar']['default']
    groups = {group['id']: group for group in bar.get('capsule_group', [])}
    samples = []
    def token(role):
        return palette['m' + ''.join(part.title() for part in role.split('_'))]
    for location in ('start', 'center', 'end'):
        for item in bar.get(location, []):
            group = groups[item[6:]] if item.startswith('group:') else None
            for name in group['members'] if group else [item]:
                widget = config.get('widget', {}).get(name, {})
                if widget.get('type') == 'spacer' or name == 'tray':
                    continue
                fill = (group.get('fill', bar.get('capsule_fill', 'surface_variant')) if group
                        else widget.get('capsule_fill', bar.get('capsule_fill', 'surface_variant')))
                alpha = (group.get('opacity', bar.get('capsule_opacity', 1)) if group
                         else widget.get('capsule_opacity', bar.get('capsule_opacity', 1)))
                foreground = (group.get('foreground') if group else None) or widget.get('capsule_foreground') or bar.get('capsule_foreground', 'on_surface')
                roles = {widget.get('color', foreground)}
                if 'icon_color' in widget:
                    roles.add(widget['icon_color'])
                if name == 'workspaces' and widget.get('style') == 'minimal':
                    roles.update(widget.get(key, 'on_surface_variant') for key in ('empty_color', 'occupied_color'))
                for backdrop in ('#000000', '#ffffff'):
                    background = composite(palette['mSurface'], backdrop, bar.get('background_opacity', 1))
                    if group or widget.get('capsule', bar.get('capsule', False)):
                        background = composite(token(fill), background, alpha)
                    for role in sorted(roles):
                        samples.append((name, role, token(role), background))
                    if name == 'workspaces' and widget.get('style', 'regular') != 'minimal':
                        # Regular workspace colors are PILL FILLS, not text colors.
                        # Noctalia picks on_<role> for accents, on_surface otherwise;
                        # empty pills multiply their fill alpha by 0.55.
                        defaults = {'focused_color': 'primary', 'occupied_color': 'secondary',
                                    'empty_color': 'surface_variant', 'urgent_color': 'error'}
                        for state, default in defaults.items():
                            fill_role = widget.get(state, default)
                            text_role = 'on_' + fill_role if fill_role in ('primary', 'secondary', 'tertiary', 'error') else 'on_surface'
                            pill = composite(token(fill_role), background, .55 if state == 'empty_color' else 1)
                            samples.append((name + '.' + state, text_role, token(text_role), pill))
    return samples


def native_surface_samples(palette, config):
    """Offline sRGB model; native 0d320287 config_types.cpp:192-214.

    Floating panel/card alpha is enum-controlled, not a numeric TOML setting.
    Outlines/shadows are decorative; check text and OSD glyph/progress instead.
    This models settled surfaces, not compositor blur or animation frames.
    """
    mode = config.get('shell', {}).get('panel', {}).get('transparency_mode', 'solid')
    panel_alpha, card_alpha = {'solid': (1., 1.), 'soft': (.80, .88),
                               'glass': (.55, .65)}[mode]
    for backdrop in ('#000000', '#ffffff'):
        panel = composite(palette['mSurface'], backdrop, panel_alpha)
        surfaces = {'panel': panel,
                    'control_center.card': composite(palette['mSurface'], panel, card_alpha),
                    'control_center.sidebar': composite(palette['mSurfaceVariant'], panel, card_alpha)}
        for name in ('notification', 'osd'):
            surfaces[name] = composite(palette['mSurface'], backdrop,
                                       config.get(name, {}).get('background_opacity', .97))
        for name, background in surfaces.items():
            for role in ('mOnSurface', 'mOnSurfaceVariant'):
                yield name, 'text', role, palette[role], background
        # osd_overlay.cpp:769-782: over-limit value text and glyphs use Error.
        yield 'osd', 'text', 'mError', palette['mError'], surfaces['osd']
        for role in ('mPrimary', 'mError', 'mOnSurfaceVariant'):
            yield 'osd.glyph', 'essential', role, palette[role], surfaces['osd']
            yield 'osd.progress', 'essential', role, palette[role], palette['mSurfaceVariant']


class NativeContrastTest(TestCase):
    def test_compositing_endpoints_and_reference_contrast(self):
        self.assertEqual(composite('#123456', '#abcdef', 0), '#abcdef')
        self.assertEqual(composite('#123456', '#abcdef', 1), '#123456')
        self.assertEqual(composite('#ffffff', '#000000', .5), '#808080')
        self.assertEqual(contrast('#ffffff', '#000000'), 21)
        self.assertEqual(contrast('#123456', '#123456'), 1)

    def test_native_glass_failure_and_soft_text_fallback(self):
        palette = {'mSurface': '#101010', 'mSurfaceVariant': '#181818',
                   'mOnSurface': '#eeeeee', 'mOnSurfaceVariant': '#cccccc',
                   'mPrimary': '#8ad6b6', 'mError': '#ffb4ab'}
        minima = {}
        for mode in ('glass', 'soft'):
            config = {'shell': {'panel': {'transparency_mode': mode}}}
            minima[mode] = min(contrast(fg, bg) for _, kind, _, fg, bg
                               in native_surface_samples(palette, config) if kind == 'text')
        self.assertLess(minima['glass'], 4.5)
        self.assertGreaterEqual(minima['soft'], 4.5)
        palette['mPrimary'] = palette['mSurface']
        self.assertLess(min(contrast(fg, bg) for _, kind, _, fg, bg
                            in native_surface_samples(palette, config) if kind == 'essential'), 3)


def check(desktop=True):
    hyprland = (ROOT / 'config/hypr/hyprland.lua').read_text()
    assert hyprland.count('require("noctalia").apply_theme()') == 1
    assert 'require("config.colors").apply_theme()' not in hyprland
    shell_config = tomllib.loads((ROOT / 'config/noctalia/config.toml').read_text())
    kitty_opacity = float(re.search(r'^background_opacity\s+([\d.]+)',
                         (ROOT / 'config/kitty/kitty.conf').read_text(), re.M)[1])
    pairs = [('mOnSurface', 'mSurface'), ('mOnSurfaceVariant', 'mSurfaceVariant'),
             ('mOnPrimary', 'mPrimary'), ('mOnSecondary', 'mSecondary'),
             ('mOnError', 'mError'), ('mOnHover', 'mHover')]
    fixtures = [('cool', '#14263e', '#77a6ca'), ('warm', '#382019', '#c29a6a'),
                ('green', '#142c22', '#83ad81'), ('muted', '#292a2c', '#a0a1a3'),
                ('bright', '#f6efdc', '#c9dfea'), ('dark', '#000000', '#101010'),
                ('busy', '#26203a', '#d79b79'), ('pastel', '#f0d8e8', '#d5e9ee'),
                ('neon', '#ff00e5', '#00ff85'), ('grayscale', '#111111', '#efefef'),
                ('muddy', '#4a493c', '#6a6454'), ('complementary', '#f4ab34', '#3152b6')]
    report = []
    with tempfile.TemporaryDirectory(prefix='adaptive-palette-') as directory:
        scratch = Path(directory)
        config, data = scratch / 'config', scratch / 'data'
        env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                   XDG_STATE_HOME=str(scratch / 'state'), XDG_RUNTIME_DIR=str(scratch / 'runtime'),
                   XDG_CACHE_HOME=str(scratch / 'cache'), HOME=str(scratch),
                   PYTHONDONTWRITEBYTECODE='1')
        for name in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY',
                     'DBUS_SESSION_BUS_ADDRESS', 'NOCTALIA_CONFIG_HOME', 'NOCTALIA_STATE_HOME'):
            env.pop(name, None)
        diagnostics = run(['noctalia', 'config', 'validate', str(ROOT / 'config/noctalia/config.toml')], env)
        # This native build exits zero for unknown keys/range warnings too.
        assert not re.search(r'\b(?:WARN|ERROR)\b', diagnostics), diagnostics
        for app in ('hypr', 'noctalia/palettes', 'kitty', 'alacritty', 'micro/colorschemes',
                    'gtk-3.0', 'gtk-4.0', 'qt6ct', 'btop'):
            (config / app).mkdir(parents=True, exist_ok=True)
        templates = []
        for name, source, output in [('hypr', 'hyprland-colors.conf', 'hypr/colors.conf'),
                                      ('noctalia', 'noctalia-palette.json', 'noctalia/palettes/matugen.json')]:
            templates.append(f'[templates.{name}]\ninput_path = {json.dumps(str(ROOT / "config/matugen/templates" / source))}\noutput_path = {json.dumps(str(config / output))}\n')
        matugen_config = scratch / 'matugen.toml'
        custom = tomllib.loads((ROOT / 'config/matugen/config.toml').read_text()).get('config', {}).get('custom_colors', {})
        custom_config = '[config.custom_colors]\n' + ''.join(
            f'{name} = {{ color = {json.dumps(value["color"])}, blend = {str(value["blend"]).lower()} }}\n'
            for name, value in custom.items())
        micro_template = ROOT / 'config/matugen/templates/micro.micro'
        if micro_template.exists():
            templates.append(f'[templates.micro]\ninput_path = {json.dumps(str(micro_template))}\n'
                             f'output_path = {json.dumps(str(config / "micro/colorschemes/adaptive.micro"))}\n')
        matugen_config.write_text('[config.wallpaper]\ncommand = "true"\narguments = []\nset = false\n' + custom_config + '\n'.join(templates))
        catalog = {'theme': {'templates': {'builtin_ids': ['hyprland', 'kitty', 'gtk3', 'gtk4',
                                                         'qt', 'kcolorscheme', 'alacritty', 'btop']}}}
        for name, low, high in fixtures:
            image = scratch / f'{name}.png'
            args = ['magick', '-size', '480x270', f'gradient:{low}-{high}']
            if name == 'busy': args += ['-wave', '12x8', '-swirl', '90']
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
                for widget, role, foreground, background in bar_contrast_samples(colors, shell_config):
                    ratio = contrast(foreground, background)
                    assert ratio >= 4.5, (name, mode, widget, role, foreground, background, ratio)
                    ratios.append(ratio)
                native_ratios = {}
                failures = []
                for surface, kind, role, foreground, background in native_surface_samples(colors, shell_config):
                    ratio = contrast(foreground, background)
                    key = surface + '.' + kind
                    native_ratios[key] = min(native_ratios.get(key, 21.), ratio)
                    threshold = 4.5 if kind == 'text' else 3.
                    if ratio < threshold:
                        failures.append(f'{surface}/{role} {foreground} on {background}: {ratio:.2f} < {threshold}')
                for backdrop in ('#000000', '#ffffff'):
                    terminal_background = composite(terminal['background'], backdrop, kitty_opacity)
                    ratios.append(contrast(terminal['foreground'], terminal_background))
                    for color in ('red', 'green', 'yellow', 'blue', 'magenta', 'cyan'):
                        ratios.append(contrast(terminal['normal'][color], terminal_background))
                if custom:
                    assert len({terminal['normal'][key] for key in ('red', 'green', 'yellow', 'blue', 'magenta', 'cyan')}) == 6
                if micro_template.exists():
                    micro = (config / 'micro/colorschemes/adaptive.micro').read_text()
                    assert f'color-link default "{colors["mOnSurface"]},{colors["mSurface"]}"' in micro
                    assert all(re.fullmatch(r'color-link [\w.-]+ "#[0-9a-fA-F]{6}(?:,#[0-9a-fA-F]{6})?"', line)
                               for line in micro.splitlines() if line and not line.startswith('#'))
                assert min(ratios) >= 4.5, (name, mode, min(ratios))
                native_command = ['noctalia', 'theme', str(image), '--theme-json', str(palette_path),
                                  '--both', '--default-mode', mode]
                native = json.loads(run(native_command, env))
                for role in ('primary', 'error', 'surface', 'on_surface', 'surface_variant', 'on_surface_variant'):
                    key = 'm' + ''.join(part.title() for part in role.split('_'))
                    assert native[mode][role] == colors[key], (name, mode, role)
                rendered = scratch / f'{name}-{mode}'
                rendered.mkdir()
                with patch.object(theme, 'command', lambda args: run(args, env).strip()):
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
                               'native_surface_contrast': {k: round(v, 2) for k, v in native_ratios.items()},
                               'contrast_failures': failures,
                               'native_templates_rendered': len(expected)})
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-desktop', action='store_true', help='Compatibility flag; validation runs without a display')
    results = check(desktop=not parser.parse_args().no_desktop)
    if os.environ.get('RICE_MATRIX_REPORT'):
        Path(os.environ['RICE_MATRIX_REPORT']).write_text(json.dumps(results, indent=2) + '\n')
    failures = [f'{row["fixture"]}/{row["mode"]}: {failure}'
                for row in results for failure in row['contrast_failures']]
    if failures:
        raise SystemExit('\n'.join(failures))
