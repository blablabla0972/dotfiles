#!/usr/bin/env python3
"""Noctalia supplies colors; this helper synchronizes Rofi/Hyprlock and awww."""
import argparse
import fcntl
import hashlib
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
import uuid


def command(argv):
    result = subprocess.check_output(argv, stderr=subprocess.STDOUT, timeout=30).decode().strip()
    if result.lower().startswith('error:'):
        raise RuntimeError(result)
    return result


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
            for key in ['gtk-theme', 'color-scheme']:
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


def palette_for(wallpaper):
    config = tomllib.loads(command(['noctalia', 'config', 'export', 'full']))
    theme_config = config.get('theme', {})
    if theme_config.get('source', 'wallpaper') != 'wallpaper' or theme_config.get('mode', 'dark') != 'dark':
        raise RuntimeError('This wallpaper helper requires the configured dark wallpaper theme')
    allowed = {'hyprland', 'kitty', 'gtk3', 'gtk4', 'qt', 'kcolorscheme', 'btop', 'alacritty'}
    configured = theme_config.get('templates', {})
    if (set(configured.get('builtin_ids', [])).difference(allowed) or configured.get('community_ids', [])
            or configured.get('user_templates', [])):
        raise RuntimeError('Additional theme templates need backup paths before transactional wallpaper switching')
    argv = ['noctalia', 'theme', str(wallpaper), '--dark', '--scheme', theme_config.get('wallpaper_scheme', 'm3-content')]
    if theme_config.get('pure_black_dark', False): argv.append('--pure-black')
    if config.get('accessibility', {}).get('high_contrast', False):
        raise RuntimeError('High-contrast theme needs a matching CLI generator before wallpaper switching')
    palette = json.loads(command(argv))
    required = {'primary', 'surface', 'on_surface', 'secondary', 'on_secondary', 'error', 'on_error'}
    if not isinstance(palette, dict) or not required.issubset(palette):
        raise ValueError('Noctalia returned an incomplete palette')
    colors = {k: v for k, v in palette.items() if not k.startswith('terminal_') and k not in {'source_color', 'background', 'on_background'}}
    for key, value in colors.items():
        if not re.fullmatch(r'[a-z][a-z0-9_]*', key) or not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            raise ValueError(f'Invalid palette token: {key}')
    return colors, config, argv


def render_colors(wallpaper, colors, config_dir):
    rofi = '* {\n' + ''.join(f'    {k.replace("_", "-")}: {v};\n' for k, v in colors.items()) + '}\n'
    hypr = f'$image = {wallpaper}\n\n' + ''.join(f'${k} = rgba({v[1:]}ff)\n' for k, v in colors.items())
    atomic_write(config_dir / 'rofi/colors.rasi', rofi.encode())
    atomic_write(config_dir / 'hypr/colors.conf', hypr.encode())


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


def mark_ready(runtime):
    request_file = runtime / 'noctalia-theme-request.json'
    if not request_file.exists(): return
    try:
        request = json.loads(request_file.read_text())
        if command(['noctalia', 'msg', 'wallpaper-get']) != request['wallpaper']: return
        for name, digest in request['expected'].items():
            if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest: return
        atomic_write(runtime / 'noctalia-theme-ready.json', json.dumps({'nonce': request['nonce']}).encode())
    except (OSError, ValueError, subprocess.SubprocessError):
        return


def wait_for_templates(nonce, runtime):
    # colors_changed is fired AFTER Noctalia's worker and catalog hooks have drained.
    deadline = time.monotonic() + 30
    while True:
        try:
            ready = json.loads((runtime / 'noctalia-theme-ready.json').read_text())
            if ready.get('nonce') == nonce: return
        except (OSError, ValueError):
            pass
        if time.monotonic() >= deadline:
            raise TimeoutError('Noctalia did not confirm completion of templates and hooks')
        time.sleep(0.15)


def quiesce_shell():
    """Emergency rollback only: drain native writers before restoring their files."""
    try: pids = command(['pgrep', '-u', str(os.getuid()), '-x', 'noctalia']).split()
    except subprocess.CalledProcessError: pids = []
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


def apply(wallpaper, colors, config, theme_command, config_dir, state_dir, runtime):
    share = Path(os.environ.get('XDG_DATA_HOME', str(Path(os.path.expanduser('~')) / '.local/share')))
    link = config_dir / 'hypr/current_wallpaper'
    old_wallpaper = link.resolve() if link.exists() else None
    names = ['hypr/current_wallpaper', 'hypr/colors.conf', 'hypr/noctalia.lua', 'hypr/hyprland.lua',
             'rofi/colors.rasi', 'rofi/wallpaper_thumb.jpg', 'kitty/kitty.conf', 'kitty/themes/noctalia.conf',
             'gtk-3.0/gtk.css', 'gtk-3.0/noctalia.css', 'gtk-4.0/gtk.css', 'gtk-4.0/noctalia.css',
             'qt5ct/colors/noctalia.conf', 'qt6ct/colors/noctalia.conf', 'kdeglobals',
             'btop/btop.conf', 'btop/themes/noctalia.theme', 'alacritty/alacritty.toml', 'alacritty/themes/noctalia.toml']
    snapshot = Snapshot([config_dir / p for p in names] + [state_dir / 'noctalia/settings.toml', share / 'color-schemes/noctalia.colors'], state_dir)
    thumb = config_dir / 'rofi/wallpaper_thumb.jpg'
    staged_thumb = snapshot.directory / 'thumbnail.jpg'
    changed_backend = False
    changed_noctalia = False
    try:
        expected = stage_native(theme_command, config, config_dir, share, snapshot.directory)
        nonce = uuid.uuid4().hex
        atomic_write(runtime / 'noctalia-theme-request.json', json.dumps({'nonce': nonce, 'wallpaper': str(wallpaper), 'expected': expected}).encode())
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
        wait_for_templates(nonce, runtime)
        command(['hyprctl', 'reload', 'config-only'])
        errors = command(['hyprctl', 'configerrors'])
        if errors: raise RuntimeError(errors)
        render_colors(wallpaper, colors, config_dir)
        if staged_thumb.exists(): atomic_write(thumb, staged_thumb.read_bytes())
        atomic_link(link, str(wallpaper))
        print('WALLPAPER_AND_THEME_OK', wallpaper, '\nBACKUP', snapshot.directory)
    except Exception:
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
        request = runtime / 'noctalia-theme-request.json'
        if request.exists(): request.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply-wallpaper', action='store_true')
    parser.add_argument('--mark-ready', action='store_true')
    parser.add_argument('wallpaper', nargs='?')
    args = parser.parse_args()
    home = Path(os.path.expanduser('~'))
    config_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    state_dir = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state')))
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', str(state_dir / 'desktop-wallpaper/runtime')))
    if args.mark_ready:
        mark_ready(runtime)
        return 0
    try:
        wallpaper = Path(args.wallpaper) if args.wallpaper else config_dir / 'hypr/current_wallpaper'
        wallpaper = wallpaper.expanduser().resolve(strict=True)
        if not wallpaper.is_file() or '\n' in str(wallpaper) or '\r' in str(wallpaper):
            raise ValueError('Wallpaper must be a regular image file with a single-line path')
        runtime.mkdir(parents=True, exist_ok=True)
        with (runtime / 'noctalia-wallpaper-apply.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            colors, config, theme_command = palette_for(wallpaper)
            if args.apply_wallpaper:
                apply(wallpaper, colors, config, theme_command, config_dir, state_dir, runtime)
            else:
                snap = Snapshot([config_dir / 'rofi/colors.rasi', config_dir / 'hypr/colors.conf'], state_dir)
                try: render_colors(wallpaper, colors, config_dir)
                except Exception:
                    snap.restore()
                    raise
        return 0
    except Exception as error:
        print('Wallpaper/theme update failed:', error, file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
