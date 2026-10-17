#!/usr/bin/env python3
"""Generate Matugen's Noctalia palette and synchronize desktop theme outputs."""
import argparse
import configparser
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import tomllib


def command(argv):
    try:
        result = subprocess.run(argv, check=True, capture_output=True, text=True, timeout=30)
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or '').strip()
        raise RuntimeError(detail or f'Command failed with exit code {error.returncode}') from error
    output = result.stdout.strip()
    if output.lower().startswith('error:'):
        raise RuntimeError(output)
    return output


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, path.stat().st_mode & 0o777 if path.exists() else 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


class Snapshot:
    def __init__(self, paths, state_dir):
        root = state_dir / 'desktop-wallpaper/backups'
        root.mkdir(parents=True, exist_ok=True)
        self.directory = Path(tempfile.mkdtemp(prefix=time.strftime('%Y%m%d-%H%M%S-'), dir=root))
        self.entries = {}
        for index, path in enumerate(dict.fromkeys(paths)):
            if path.is_symlink():
                self.entries[str(path)] = {'link': os.readlink(path)}
            elif path.is_file():
                copy = self.directory / str(index)
                shutil.copy2(path, copy)
                assert path.read_bytes() == copy.read_bytes()
                self.entries[str(path)] = {'copy': str(copy), 'mode': path.stat().st_mode & 0o777}
            elif path.exists():
                raise RuntimeError(f'Expected file, found directory: {path}')
            else:
                self.entries[str(path)] = {'new': True}
        (self.directory / 'manifest.json').write_text(json.dumps(self.entries, indent=2))
        self.appearance = {}
        if shutil.which('gsettings'):
            for key in ['gtk-theme', 'color-scheme', 'icon-theme']:
                self.appearance[key] = command(['gsettings', 'get', 'org.gnome.desktop.interface', key])
        (self.directory / 'appearance.json').write_text(json.dumps(self.appearance))

    def restore(self):
        for name, entry in self.entries.items():
            path = Path(name)
            if 'link' in entry:
                atomic_link(path, entry['link'])
            elif 'copy' in entry:
                if path.is_symlink(): path.unlink()
                atomic_write(path, Path(entry['copy']).read_bytes())
                os.chmod(path, entry['mode'])
            elif path.is_file() or path.is_symlink():
                # Remove only a generated leaf which did not exist before this transaction.
                path.unlink()
        for key, value in self.appearance.items():
            command(['gsettings', 'set', 'org.gnome.desktop.interface', key, value])


def atomic_link(path, target):
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    os.close(fd)
    os.unlink(temp)
    try:
        os.symlink(target, temp)
        os.replace(temp, path)
    finally:
        if os.path.lexists(temp): os.unlink(temp)


def palette_for(wallpaper, config_dir):
    config = tomllib.loads(command(['noctalia', 'config', 'export', 'full']))
    theme_config = config.get('theme', {})
    if theme_config.get('source') != 'wallpaper' or theme_config.get('matugen_palette') != 'matugen':
        raise RuntimeError('Noctalia must use source=wallpaper with matugen_palette=matugen')
    allowed = {'hyprland', 'kitty', 'gtk3', 'gtk4', 'qt', 'kcolorscheme', 'btop', 'alacritty'}
    configured = theme_config.get('templates', {})
    if (set(configured.get('builtin_ids', [])).difference(allowed) or configured.get('community_ids', [])
            or configured.get('user_templates', [])):
        raise RuntimeError('Additional theme templates need backup paths before transactional wallpaper switching')
    if config.get('accessibility', {}).get('high_contrast', False):
        raise RuntimeError('High-contrast theme needs a matching Matugen template before wallpaper switching')

    mode = theme_config.get('mode', 'dark')
    if mode == 'auto':
        try:
            mode = command(['noctalia', 'msg', 'theme-mode-get'])
        except subprocess.SubprocessError:
            mode = 'dark'
    if mode not in {'dark', 'light'}:
        raise ValueError(f'Unsupported Noctalia theme mode: {mode}')

    palette_path = config_dir / 'noctalia/palettes/matugen.json'
    previous_palette = palette_path.read_bytes() if palette_path.is_file() else None
    matugen_config = config_dir / 'matugen/config.toml'
    command([
        'matugen', 'image', str(wallpaper), '--config', str(matugen_config),
        '--mode', mode, '--prefer', 'less-saturation', '--source-color-index', '0', '--quiet',
    ])
    palette_json = json.loads(palette_path.read_text())
    required_fixed_roles = {
        'mPrimary', 'mOnPrimary', 'mSecondary', 'mOnSecondary', 'mTertiary', 'mOnTertiary',
        'mError', 'mOnError', 'mSurface', 'mOnSurface', 'mSurfaceVariant', 'mOnSurfaceVariant',
        'mOutline', 'mHover', 'mOnHover',
    }
    if not isinstance(palette_json, dict) or not all(
            isinstance(palette_json.get(key), dict) and required_fixed_roles.issubset(palette_json[key])
            for key in ('dark', 'light')):
        raise ValueError('Matugen returned an incomplete Noctalia custom palette')

    required_terminal_roles = {'foreground', 'background', 'cursor', 'cursorText', 'selectionFg', 'selectionBg'}
    required_terminal_colors = {'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'}

    def has_terminal_palette(mode_palette):
        terminal = mode_palette.get('terminal') if isinstance(mode_palette, dict) else None
        if not isinstance(terminal, dict) or not required_terminal_roles.issubset(terminal):
            return False
        return all(
            isinstance(terminal.get(group), dict) and required_terminal_colors.issubset(terminal[group])
            for group in ('normal', 'bright')
        )

    if not all(has_terminal_palette(palette_json[mode_name]) for mode_name in ('dark', 'light')):
        raise ValueError('Matugen returned an incomplete Noctalia terminal palette')

    theme_command = [
        'noctalia', 'theme', str(wallpaper), '--theme-json', str(palette_path), '--both',
        '--default-mode', mode,
    ]
    palette = json.loads(command(theme_command))
    if not isinstance(palette, dict) or not all(isinstance(palette.get(key), dict) for key in ('dark', 'light')):
        raise ValueError('Noctalia could not resolve the Matugen custom palette')
    required = {'primary', 'surface', 'on_surface', 'secondary', 'on_secondary', 'error', 'on_error'}
    if not all(required.issubset(palette[key]) for key in ('dark', 'light')):
        raise ValueError('Noctalia returned an incomplete palette')
    for mode_name in ('dark', 'light'):
        for key, value in palette[mode_name].items():
            if not re.fullmatch(r'[a-z][a-z0-9_]*', key) or not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
                raise ValueError(f'Invalid palette token: {key}')
    changed = previous_palette != palette_path.read_bytes()
    return palette, config, theme_command, changed, mode


def reload_matugen_palette(config, changed):
    theme = config.get('theme', {})
    if theme.get('source') != 'wallpaper' or theme.get('matugen_palette') != 'matugen':
        raise RuntimeError('Refusing to change Noctalia palette source; expected wallpaper + Matugen override')
    if changed:
        command(['noctalia', 'msg', 'color-palette-reload'])


def sync_toolkit_settings(config_dir, mode):
    """Remove stale dark-only preferences while keeping other application settings."""
    icons = 'Papirus-Dark' if mode == 'dark' else 'Papirus'
    for app in ('gtk-3.0', 'gtk-4.0', 'qt5ct', 'qt6ct'):
        path = config_dir / app / ('settings.ini' if app.startswith('gtk') else f'{app}.conf')
        if not path.parent.is_dir() or (app.startswith('qt') and not path.is_file()):
            continue
        ini = configparser.ConfigParser(interpolation=None)
        ini.optionxform = str
        ini.read(path)
        section = 'Settings' if app.startswith('gtk') else 'Appearance'
        if not ini.has_section(section): ini.add_section(section)
        if app.startswith('gtk'):
            ini[section]['gtk-theme-name'] = 'adw-gtk3-dark' if mode == 'dark' else 'adw-gtk3'
            ini[section]['gtk-application-prefer-dark-theme'] = str(int(mode == 'dark'))
        if (Path('/usr/share/icons') / icons).is_dir():
            ini[section]['gtk-icon-theme-name' if app.startswith('gtk') else 'icon_theme'] = icons
        output = io.StringIO()
        ini.write(output, space_around_delimiters=False)
        atomic_write(path, (output.getvalue().rstrip() + '\n').encode())
    if shutil.which('gsettings') and (Path('/usr/share/icons') / icons).is_dir():
        command(['gsettings', 'set', 'org.gnome.desktop.interface', 'icon-theme', icons])


def stage_native(theme_command, config, config_dir, data_dir, directory):
    base = Path('/usr/share/noctalia/assets/templates')
    catalog = tomllib.loads((base / 'builtin.toml').read_text())['templates']
    specs, expected = [], {}
    ids = config['theme'].get('templates', {}).get('builtin_ids', [])
    for name in ids:
        entry = catalog[name]
        if name == 'hyprland':
            source, outputs = base / 'hyprland/hyprland.lua', [str(config_dir / 'hypr/noctalia.lua')]
        else:
            source = base / entry['input_path']
            values = entry['output_path']
            outputs = values if isinstance(values, list) else [values]
            outputs = [v.replace('$XDG_CONFIG_HOME', str(config_dir)).replace('$XDG_DATA_HOME', str(data_dir)) for v in outputs]
        for output in outputs:
            target = Path(output)
            # Match native templates' installed-client gate, without creating new apps' configs.
            if target.is_relative_to(config_dir) and not (config_dir / target.relative_to(config_dir).parts[0]).is_dir():
                continue
            staged = directory / ('expected-' + str(len(expected)))
            expected[str(target)] = staged
            specs += ['-r', str(source) + ':' + str(staged)]
    if not expected:
        raise RuntimeError('No enabled native templates to verify')
    # Individual --render does not execute catalog hooks or touch live files.
    command(theme_command + specs)
    return {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in expected.items()}


def wait_for_templates(wallpaper, expected, mode=None):
    # Wait for Noctalia's native templates to match the Matugen-backed palette.
    deadline = time.monotonic() + 30
    while True:
        try:
            if (command(['noctalia', 'msg', 'wallpaper-get']) == str(wallpaper)
                    and (mode is None or command(['noctalia', 'msg', 'theme-mode-get']) == mode) and all(
                    hashlib.sha256(Path(name).read_bytes()).hexdigest() == digest
                    for name, digest in expected.items())):
                return
        except (OSError, subprocess.SubprocessError):
            pass
        if time.monotonic() >= deadline:
            raise TimeoutError('Noctalia did not apply the native templates for the selected wallpaper')
        time.sleep(0.15)


def quiesce_shell():
    """Emergency rollback only: drain native writers before restoring their files."""
    try: pids = command(['pgrep', '-u', str(os.getuid()), '-x', 'noctalia']).split()
    except RuntimeError as error:
        if isinstance(error.__cause__, subprocess.CalledProcessError) and error.__cause__.returncode == 1:
            return False
        raise
    if not pids: return False
    if json.loads(command(['noctalia', 'msg', 'status'])).get('locked', True):
        raise RuntimeError('Will not stop Noctalia while it is locking the session')
    for value in pids: os.kill(int(value), signal.SIGTERM)
    deadline = time.monotonic() + 30
    while any(Path('/proc/' + value).exists() for value in pids):
        if time.monotonic() >= deadline:
            raise TimeoutError('Noctalia has not finished draining writers; snapshot retained')
        time.sleep(0.1)
    return True


def theme_snapshot_paths(config_dir, state_dir):
    share = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    names = ['hypr/current_wallpaper', 'hypr/colors.conf', 'hypr/noctalia.lua', 'hypr/hyprland.lua',
             'rofi/colors.rasi', 'rofi/wallpaper_thumb.jpg', 'kitty/kitty.conf', 'kitty/themes/noctalia.conf',
             'gtk-3.0/gtk.css', 'gtk-3.0/noctalia.css', 'gtk-4.0/gtk.css', 'gtk-4.0/noctalia.css',
             'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini', 'qt5ct/qt5ct.conf', 'qt6ct/qt6ct.conf',
             'qt5ct/colors/noctalia.conf', 'qt6ct/colors/noctalia.conf', 'kdeglobals',
             'btop/btop.conf', 'btop/themes/noctalia.theme', 'alacritty/alacritty.toml', 'alacritty/themes/noctalia.toml',
             'noctalia/palettes/matugen.json']
    return (
        [config_dir / p for p in names]
        + [state_dir / 'noctalia/settings.toml', share / 'color-schemes/noctalia.colors']
    )


def apply(wallpaper, config_dir, state_dir, runtime):
    share = Path(os.environ.get('XDG_DATA_HOME', str(Path(os.path.expanduser('~')) / '.local/share')))
    link = config_dir / 'hypr/current_wallpaper'
    old_wallpaper = link.resolve() if link.exists() else None
    settings = state_dir / 'noctalia/settings.toml'
    # Capture managed settings contents while preserving the outer dotfiles symlink.
    settings_target = settings.resolve()
    snapshot = Snapshot([settings_target if p == settings else p
                         for p in theme_snapshot_paths(config_dir, state_dir)], state_dir)
    thumb = config_dir / 'rofi/wallpaper_thumb.jpg'
    staged_thumb = snapshot.directory / 'thumbnail.jpg'
    changed_backend = False
    changed_noctalia = False
    request = runtime / 'noctalia-matugen-request.json'
    mode = None
    try:
        _, config, theme_command, palette_changed, mode = palette_for(wallpaper, config_dir)
        changed_noctalia = palette_changed
        reload_matugen_palette(config, palette_changed)
        expected = stage_native(theme_command, config, config_dir, share, snapshot.directory)
        atomic_write(request, json.dumps({
            'wallpaper': str(wallpaper),
            'mode': mode,
            'palette': hashlib.sha256((config_dir / 'noctalia/palettes/matugen.json').read_bytes()).hexdigest(),
            'expires': time.time() + 45,
        }).encode())
        if old_wallpaper != wallpaper or not thumb.exists() or wallpaper.stat().st_mtime > thumb.stat().st_mtime:
            command(['magick', str(wallpaper), '-thumbnail', '1000x1000>', '-quality', '85', str(staged_thumb)])
        changed_backend = True
        duration_sec = 0.8
        command(['swww', 'img', str(wallpaper), '--transition-type', 'grow', '--transition-pos', 'center',
                 '--transition-fps', '144', '--transition-duration', str(duration_sec), '--transition-bezier', '.54,0,.34,.99'])
        
        # Calculate monotonic deadline to wait for the transition to finish
        deadline = time.monotonic() + duration_sec + 0.05
        now = time.monotonic()
        if now < deadline:
            time.sleep(deadline - now)

        # Mark before IPC: a command may persist settings before reporting failure.
        changed_noctalia = True
        command(['noctalia', 'msg', 'wallpaper-set', str(wallpaper)])
        command(['noctalia', 'msg', 'templates-apply'])
        wait_for_templates(wallpaper, expected, mode)
        sync_toolkit_settings(config_dir, mode)
        command(['hyprctl', 'reload', 'config-only'])
        errors = command(['hyprctl', 'configerrors'])
        if errors: raise RuntimeError(errors)
        if staged_thumb.exists(): atomic_write(thumb, staged_thumb.read_bytes())
        atomic_link(link, str(wallpaper))
        print('WALLPAPER_AND_THEME_OK', wallpaper, '\nBACKUP', snapshot.directory)
    except Exception:
        try:
            preserve_selection = (command(['noctalia', 'msg', 'theme-mode-get']) != mode
                                  or command(['noctalia', 'msg', 'wallpaper-get']) != str(wallpaper))
        except Exception:
            preserve_selection = True  # Unknown native state must not erase newer user intent.
        if preserve_selection:
            snapshot.entries.pop(str(settings_target), None)
            snapshot.appearance.clear()
        stopped = quiesce_shell() if changed_noctalia else False
        try:
            try:
                snapshot.restore()
            except Exception as error:
                raise RuntimeError(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}') from error
            if changed_backend and old_wallpaper and old_wallpaper.is_file():
                try:
                    command(['swww', 'img', str(old_wallpaper), '--transition-type', 'none'])
                except Exception as error: print('Wallpaper recovery needs attention:', error, file=sys.stderr)
            try: command(['hyprctl', 'reload', 'config-only'])
            except Exception as error: print('Hyprland recovery needs attention:', error, file=sys.stderr)
            print('RESTORED_SNAPSHOT', snapshot.directory, file=sys.stderr)
        finally:
            if stopped:
                subprocess.Popen(['noctalia', '-d'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        raise
    finally:
        if request.exists(): request.unlink()


def wallpaper_changed(config_dir, state_dir, runtime, mode_changed=False):
    raw_path = (None if mode_changed else os.environ.get('NOCTALIA_WALLPAPER_PATH')) or command(['noctalia', 'msg', 'wallpaper-get'])
    wallpaper = Path(raw_path).expanduser().resolve(strict=True)
    if not wallpaper.is_file() or '\n' in str(wallpaper) or '\r' in str(wallpaper):
        raise ValueError('Noctalia supplied an invalid wallpaper path')

    request = runtime / 'noctalia-matugen-request.json'
    palette_path = config_dir / 'noctalia/palettes/matugen.json'
    try:
        data = json.loads(request.read_text())
        if (not mode_changed and data.get('wallpaper') == str(wallpaper) and data.get('expires', 0) > time.time()
                and data.get('mode') == command(['noctalia', 'msg', 'theme-mode-get'])
                and data.get('palette') == hashlib.sha256(palette_path.read_bytes()).hexdigest()):
            return
    except (OSError, ValueError):
        pass

    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'noctalia-wallpaper-apply.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Discard queued events superseded by a newer native selection.
        if Path(command(['noctalia', 'msg', 'wallpaper-get'])).expanduser().resolve(strict=True) != wallpaper:
            return
        link = config_dir / 'hypr/current_wallpaper'
        old_wallpaper = link.resolve() if link.exists() else None
        # Native wallpaper selection belongs to the user, including newer selections.
        paths = [p for p in theme_snapshot_paths(config_dir, state_dir)
                 if p != state_dir / 'noctalia/settings.toml']
        snapshot = Snapshot(paths, state_dir)
        palette_changed = False
        changed_native = False
        changed_backend = False
        mode = None

        def check_selection():
            if Path(command(['noctalia', 'msg', 'wallpaper-get'])).expanduser().resolve(strict=True) != wallpaper:
                raise RuntimeError('Wallpaper event superseded by a newer selection')
            if mode is not None and command(['noctalia', 'msg', 'theme-mode-get']) != mode:
                raise RuntimeError('Theme event superseded by a newer mode')
        try:
            _, config, theme_command, palette_changed, mode = palette_for(wallpaper, config_dir)
            check_selection()
            changed_native = palette_changed
            reload_matugen_palette(config, palette_changed)
            expected = stage_native(
                theme_command, config, config_dir,
                Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))), snapshot.directory
            )
            changed_native = True
            command(['noctalia', 'msg', 'templates-apply'])
            check_selection()
            wait_for_templates(wallpaper, expected, mode)
            check_selection()
            sync_toolkit_settings(config_dir, mode)
            if not mode_changed and old_wallpaper != wallpaper:
                staged_thumb = snapshot.directory / 'thumbnail.jpg'
                command(['magick', str(wallpaper), '-thumbnail', '1000x1000>', '-quality', '85', str(staged_thumb)])
                if not config.get('wallpaper', {}).get('enabled', True):
                    changed_backend = True
                    command(['swww', 'img', str(wallpaper), '--transition-type', 'fade', '--transition-duration', '0.3'])
                check_selection()
                atomic_write(config_dir / 'rofi/wallpaper_thumb.jpg', staged_thumb.read_bytes())
                atomic_link(link, str(wallpaper))
            if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
                command(['hyprctl', 'reload', 'config-only'])
                errors = command(['hyprctl', 'configerrors'])
                if errors:
                    raise RuntimeError(errors)
        except Exception:
            stopped = quiesce_shell() if changed_native else False
            try:
                snapshot.restore()
                if changed_backend and old_wallpaper and old_wallpaper.is_file():
                    try:
                        command(['swww', 'img', str(old_wallpaper), '--transition-type', 'none'])
                    except Exception as error:
                        print('Wallpaper recovery needs attention:', error, file=sys.stderr)
            finally:
                if stopped:
                    subprocess.Popen(['noctalia', '-d'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--apply-wallpaper', action='store_true')
    action.add_argument('--wallpaper-changed', action='store_true')
    action.add_argument('--theme-mode-changed', action='store_true',
                        help='Synchronize palette outputs for the current wallpaper and theme mode')
    parser.add_argument('wallpaper', nargs='?')
    args = parser.parse_args()
    home = Path(os.path.expanduser('~'))
    config_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    state_dir = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state')))
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', str(state_dir / 'desktop-wallpaper/runtime')))
    try:
        runtime.mkdir(parents=True, exist_ok=True)
        if args.wallpaper_changed or args.theme_mode_changed:
            wallpaper_changed(config_dir, state_dir, runtime, mode_changed=args.theme_mode_changed)
            return 0
        wallpaper = Path(args.wallpaper) if args.wallpaper else config_dir / 'hypr/current_wallpaper'
        wallpaper = wallpaper.expanduser().resolve(strict=True)
        if not wallpaper.is_file() or '\n' in str(wallpaper) or '\r' in str(wallpaper):
            raise ValueError('Wallpaper must be a regular image file with a single-line path')
        runtime.mkdir(parents=True, exist_ok=True)
        with (runtime / 'noctalia-wallpaper-apply.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.apply_wallpaper:
                apply(wallpaper, config_dir, state_dir, runtime)
            else:
                palette_path = config_dir / 'noctalia/palettes/matugen.json'
                snap = Snapshot([
                    config_dir / 'rofi/colors.rasi', config_dir / 'hypr/colors.conf', palette_path,
                    state_dir / 'noctalia/settings.toml',
                ], state_dir)
                palette_changed = False
                try:
                    _, config, _, palette_changed, _ = palette_for(wallpaper, config_dir)
                    reload_matugen_palette(config, palette_changed)
                except Exception:
                    snap.restore()
                    if palette_changed:
                        try:
                            command(['noctalia', 'msg', 'color-palette-reload'])
                        except Exception as error:
                            print('Noctalia palette rollback needs attention:', error, file=sys.stderr)
                    raise
        return 0
    except Exception as error:
        print('Wallpaper/theme update failed:', error, file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
