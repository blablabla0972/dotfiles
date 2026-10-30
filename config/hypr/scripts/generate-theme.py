#!/usr/bin/env python3
"""Generate Matugen's Noctalia palette and synchronize desktop theme outputs."""
import argparse
import configparser
import contextlib
import fcntl
import hashlib
import importlib.util
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
import uuid


MATUGEN_OUTPUTS = ('hypr/colors.conf', 'noctalia/palettes/matugen.json', 'micro/colorschemes/adaptive.micro')
MATUGEN_FLAGS = ('--prefer', 'less-saturation', '--source-color-index', '0', '--quiet')


class TransactionError(RuntimeError):
    """Carry a proven rollback outcome to the request acknowledgment boundary."""
    def __init__(self, message, rolled_back, palette_revision=None):
        super().__init__(message)
        self.rolled_back = rolled_back
        self.palette_revision = palette_revision if rolled_back else None


def adaptive_path(state_dir):
    return state_dir / 'desktop-wallpaper/adaptive-theme.json'


_DERIVE_TOKENS_MODULE = None


def stage_adaptive_theme(wallpaper, config_dir, mode):
    global _DERIVE_TOKENS_MODULE
    if _DERIVE_TOKENS_MODULE is None:
        # Resolve source beside this script, including when ~/.config/hypr is a symlink.
        source = Path(__file__).resolve().parents[2] / 'rice/theme/derive_tokens.py'
        spec = importlib.util.spec_from_file_location('rice_derive_tokens', source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _DERIVE_TOKENS_MODULE = module
    else:
        module = _DERIVE_TOKENS_MODULE
    palette = (config_dir / 'noctalia/palettes/matugen.json').read_bytes()
    revision = hashlib.sha256(palette).hexdigest()
    with wallpaper.open('rb') as stream:
        wallpaper_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    # No trusted region sampler yet: the pure library selects solid-safe surfaces.
    tokens = module.derive_tokens(json.loads(palette), wallpaper_sha, revision, mode, [])
    return (json.dumps(tokens, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode(), revision


def command(argv, timeout=30):
    try:
        result = subprocess.run(argv, check=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or '').strip()
        raise RuntimeError(detail or f'Command failed with exit code {error.returncode}') from error
    output = result.stdout.strip()
    if output.lower().startswith('error:'):
        raise RuntimeError(output)
    return output


def acquire_request_lock(lock, timeout=15):
    """Fail before starting a transaction if its existing owner stays busy."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Another wallpaper transaction still owns the lock')
            time.sleep(min(0.05, remaining))


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, path.stat().st_mode & 0o777 if path.exists() else 0o600)
        os.replace(name, path)
    finally:
        if os.path.lexists(name): os.unlink(name)


class Snapshot:
    def __init__(self, paths, state_dir, link_only=()):
        root = state_dir / 'desktop-wallpaper/backups'
        root.mkdir(parents=True, exist_ok=True)
        self.directory = Path(tempfile.mkdtemp(prefix=time.strftime('%Y%m%d-%H%M%S-'), dir=root))
        self.entries = {}
        paths = list(paths)
        paths.extend(path.resolve() for path in tuple(paths) if path.is_symlink() and path not in link_only)
        for index, path in enumerate(dict.fromkeys(paths)):
            if path.is_symlink():
                self.entries[str(path)] = {'link': os.readlink(path)}
            elif path.is_file():
                copy = self.directory / str(index)
                shutil.copy2(path, copy)
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

        # Retention policy: keep at most 15 most recent backup snapshots
        retention_limit = 15
        try:
            existing = sorted(
                [p for p in root.iterdir() if p.is_dir() and p != self.directory],
                key=lambda p: p.stat().st_mtime,
                reverse=True
            )
            for old in existing[retention_limit - 1:]:
                shutil.rmtree(old, ignore_errors=True)
        except OSError:
            pass

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


def inline_toml(value):
    if isinstance(value, dict):
        return '{' + ', '.join(f'{json.dumps(key, ensure_ascii=False)} = {inline_toml(item)}' for key, item in value.items()) + '}'
    if isinstance(value, list):
        return '[' + ', '.join(inline_toml(item) for item in value) + ']'
    return json.dumps(value, ensure_ascii=False)


def matugen_cache_path(wallpaper, source, settings, mode):
    binary = shutil.which('matugen')
    if not binary:
        return None
    binary = Path(binary).resolve()
    stat = binary.stat()
    inputs = [wallpaper, source]
    inputs.extend(Path(template['input_path']) for template in settings.get('templates', {}).values())
    hashes = []
    for path in dict.fromkeys(inputs):
        with path.open('rb') as stream:
            hashes.append((str(path), hashlib.file_digest(stream, 'sha256').hexdigest()))
    identity = [1, mode, MATUGEN_FLAGS,
                str(binary), stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns,
                stat.st_ctime_ns, hashes, settings]
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    cache = Path(os.environ.get('XDG_CACHE_HOME') or str(Path.home() / '.cache'))
    return cache / 'desktop-wallpaper/matugen-v1' / (key + '.json')


def cached_matugen_outputs(cache, names):
    try:
        if cache is None or cache.stat().st_size > 1024 * 1024:
            return None
        record = json.loads(cache.read_text())
        if not isinstance(record, dict) or record.get('schema_version') != 1:
            return None
        outputs = record.get('outputs')
        if (not isinstance(outputs, dict) or set(outputs) != names
                or not all(isinstance(value, str) and value for value in outputs.values())):
            return None
        digest = hashlib.sha256(json.dumps(outputs, sort_keys=True).encode()).hexdigest()
        return outputs if record.get('sha256') == digest else None
    except (OSError, ValueError, UnicodeError):
        return None


def render_matugen(wallpaper, config_dir, mode):
    source = config_dir / 'matugen/config.toml'
    settings = tomllib.loads(source.read_text())
    home_config = Path.home() / '.config'
    outputs = {config_dir / name for name in MATUGEN_OUTPUTS}
    for template in settings.get('templates', {}).values():
        if any(template.get(hook) for hook in ('pre_hook', 'post_hook')):
            raise RuntimeError('Matugen template hooks need backup paths before transactional theme generation')
        for key in ('input_path', 'output_path'):
            if key not in template: continue
            path = Path(template[key]).expanduser()
            if path.is_relative_to(home_config):
                path = config_dir / path.relative_to(home_config)
            elif not path.is_absolute():
                path = source.parent / path
            path = Path(os.path.abspath(path))
            if key == 'output_path' and path not in outputs:
                raise RuntimeError('Additional Matugen outputs need backup paths before theme generation')
            template[key] = str(path)
    names = {name for name in MATUGEN_OUTPUTS if any(
        template.get('output_path') == str(config_dir / name)
        for template in settings.get('templates', {}).values())}
    try:
        cache = matugen_cache_path(wallpaper, source, settings, mode) if names else None
    except (OSError, ValueError):
        cache = None  # Cache availability must never prevent normal generation.
    cached = cached_matugen_outputs(cache, names)
    if cached is not None:
        for name, value in cached.items():
            target = (config_dir / name).resolve()
            contents = value.encode()
            if not target.is_file() or target.read_bytes() != contents:
                atomic_write(target, contents)
        return
    # Absolute paths keep a symlinked Matugen directory from redirecting sibling outputs.
    with tempfile.TemporaryDirectory(prefix='matugen-config-') as directory:
        config = Path(directory) / 'config.toml'
        config.write_text('\n'.join(f'{json.dumps(key, ensure_ascii=False)} = {inline_toml(value)}' for key, value in settings.items()))
        command(['matugen', 'image', str(wallpaper), '--config', str(config),
                 '--mode', mode, *MATUGEN_FLAGS])
    try:
        # Do not retain output if an input changed while Matugen was working.
        if cache is not None and matugen_cache_path(wallpaper, source, settings, mode) == cache:
            rendered = {name: (config_dir / name).read_bytes().decode('utf-8') for name in names}
            record = dict(schema_version=1, outputs=rendered,
                          sha256=hashlib.sha256(json.dumps(rendered, sort_keys=True).encode()).hexdigest())
            atomic_write(cache, json.dumps(record, ensure_ascii=False).encode())
    except (OSError, ValueError, UnicodeError):
        pass


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
        except (RuntimeError, subprocess.SubprocessError, OSError):
            mode = 'dark'
    if mode not in {'dark', 'light'}:
        raise ValueError(f'Unsupported Noctalia theme mode: {mode}')

    palette_path = config_dir / 'noctalia/palettes/matugen.json'
    previous_palette = palette_path.read_bytes() if palette_path.is_file() else None
    render_matugen(wallpaper, config_dir, mode)
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
    icon_dirs = [
        Path('/usr/share/icons'),
        Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'icons',
        Path.home() / '.icons',
    ]
    icon_available = any((d / icons).is_dir() for d in icon_dirs)

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
        if icon_available:
            ini[section]['gtk-icon-theme-name' if app.startswith('gtk') else 'icon_theme'] = icons
        output = io.StringIO()
        ini.write(output, space_around_delimiters=False)
        target = path.resolve()
        contents = (output.getvalue().rstrip() + '\n').encode()
        try:
            unchanged = target.read_bytes() == contents
        except OSError:
            unchanged = False
        if not unchanged:
            atomic_write(target, contents)
    if shutil.which('gsettings') and icon_available:
        try:
            command(['gsettings', 'set', 'org.gnome.desktop.interface', 'icon-theme', icons])
        except (RuntimeError, subprocess.SubprocessError, OSError):
            pass


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
        except (RuntimeError, OSError, subprocess.SubprocessError):
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


def restart_shell():
    launcher = subprocess.Popen(['noctalia', '-d'], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    # -d may exit zero after daemonizing; only a responding IPC proves readiness.
    for _ in range(20):
        if launcher.poll() not in (None, 0):
            raise RuntimeError('Noctalia restart launcher failed')
        try:
            ready = isinstance(json.loads(command(['noctalia', 'msg', 'status'], timeout=.5)), dict)
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
            ready = False
        if launcher.poll() not in (None, 0):
            raise RuntimeError('Noctalia restart launcher failed')
        if ready:
            return
        time.sleep(.1)
    raise TimeoutError('Noctalia restart IPC did not become ready')


def theme_snapshot_paths(config_dir, state_dir):
    share = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    names = ['hypr/current_wallpaper', 'hypr/noctalia.lua', 'hypr/hyprland.lua',
             'kitty/kitty.conf', 'kitty/themes/noctalia.conf',
             'gtk-3.0/gtk.css', 'gtk-3.0/noctalia.css', 'gtk-4.0/gtk.css', 'gtk-4.0/noctalia.css',
             'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini', 'qt5ct/qt5ct.conf', 'qt6ct/qt6ct.conf',
             'qt5ct/colors/noctalia.conf', 'qt6ct/colors/noctalia.conf', 'kdeglobals',
             'btop/btop.conf', 'btop/themes/noctalia.theme', 'alacritty/alacritty.toml', 'alacritty/themes/noctalia.toml']
    return (
        [config_dir / p for p in (*names, *MATUGEN_OUTPUTS)]
        + [state_dir / 'noctalia/settings.toml', share / 'color-schemes/noctalia.colors', adaptive_path(state_dir)]
    )


def apply(wallpaper, config_dir, state_dir, runtime):
    share = Path(os.environ.get('XDG_DATA_HOME', str(Path(os.path.expanduser('~')) / '.local/share')))
    link = config_dir / 'hypr/current_wallpaper'
    old_wallpaper = link.resolve() if link.exists() else None
    settings = state_dir / 'noctalia/settings.toml'
    # Capture managed settings contents while preserving the outer dotfiles symlink.
    settings_target = settings.resolve()
    snapshot = Snapshot([settings_target if p == settings else p
                         for p in theme_snapshot_paths(config_dir, state_dir)], state_dir, link_only=(link,))
    changed_backend = False
    changed_noctalia = False
    request = runtime / 'noctalia-matugen-request.json'
    mode = None
    palette_path = config_dir / 'noctalia/palettes/matugen.json'
    previous_revision = hashlib.sha256(palette_path.read_bytes()).hexdigest() if palette_path.is_file() else None
    try:
        # Start the wallpaper transition while palette and theme files are prepared.
        duration_sec = 1.8
        changed_backend = True
        command(['swww', 'img', str(wallpaper), '--transition-type', 'grow', '--transition-pos', 'center',
                 '--transition-fps', '144', '--transition-duration', str(duration_sec), '--transition-bezier', '.54,0,.34,.99'])
        deadline = time.monotonic() + duration_sec + 0.05

        _, config, theme_command, palette_changed, mode = palette_for(wallpaper, config_dir)
        changed_noctalia = palette_changed
        adaptive, revision = stage_adaptive_theme(wallpaper, config_dir, mode)
        reload_matugen_palette(config, palette_changed)
        expected = stage_native(theme_command, config, config_dir, share, snapshot.directory)
        atomic_write(request, json.dumps({
            'wallpaper': str(wallpaper),
            'mode': mode,
            'palette': hashlib.sha256((config_dir / 'noctalia/palettes/matugen.json').read_bytes()).hexdigest(),
            'expires': time.time() + 45,
        }).encode())

        # Wait only for whatever remains of the transition after theme preparation.
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
        if (command(['noctalia', 'msg', 'wallpaper-get']) != str(wallpaper)
                or command(['noctalia', 'msg', 'theme-mode-get']) != mode):
            raise RuntimeError('Theme transaction superseded by a newer native selection')
        atomic_link(link, str(wallpaper))
        atomic_write(adaptive_path(state_dir), adaptive)
        print('WALLPAPER_AND_THEME_OK', wallpaper, '\nBACKUP', snapshot.directory)
        return revision
    except Exception as cause:
        try:
            preserve_selection = (command(['noctalia', 'msg', 'theme-mode-get']) != mode
                                  or command(['noctalia', 'msg', 'wallpaper-get']) != str(wallpaper))
        except Exception:
            preserve_selection = True  # Unknown native state must not erase newer user intent.
        if preserve_selection:
            snapshot.entries.pop(str(settings_target), None)
            snapshot.appearance.clear()
        stopped = False
        restored = False
        try:
            stopped = quiesce_shell() if changed_noctalia else False
            snapshot.restore()
            if changed_backend:
                if not old_wallpaper or not old_wallpaper.is_file():
                    raise RuntimeError('Previous wallpaper is unknown; managed files restored but backend recovery cannot be verified')
                command(['swww', 'img', str(old_wallpaper), '--transition-type', 'none'])
            restored = True
        except Exception as error:
            print(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}', file=sys.stderr)
        if stopped:
            try:
                restart_shell()
            except Exception as error:
                restored = False
                print(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}', file=sys.stderr)
        if restored:
            try:
                command(['hyprctl', 'reload', 'config-only'])
                errors = command(['hyprctl', 'configerrors'])
                if errors: raise RuntimeError(errors)
            except Exception as error:
                restored = False
                print(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}', file=sys.stderr)
        if restored:
            print('RESTORED_SNAPSHOT', snapshot.directory, file=sys.stderr)
        raise TransactionError(str(cause), restored, previous_revision) from cause
    finally:
        try:
            request.unlink(missing_ok=True)
        except OSError as error:
            # The expiring event marker must not replace a proven transaction outcome.
            print('Wallpaper request cleanup needs attention:', error, file=sys.stderr)


def wallpaper_changed(config_dir, state_dir, runtime, mode_changed=False):
    raw_path = (None if mode_changed else os.environ.get('NOCTALIA_WALLPAPER_PATH')) or command(['noctalia', 'msg', 'wallpaper-get'])
    wallpaper = Path(raw_path).expanduser().resolve(strict=True)
    if not wallpaper.is_file() or '\n' in str(wallpaper) or '\r' in str(wallpaper):
        raise ValueError('Noctalia supplied an invalid wallpaper path')

    request = runtime / 'noctalia-matugen-request.json'
    palette_path = config_dir / 'noctalia/palettes/matugen.json'
    try:
        data = json.loads(request.read_text())
        if (not mode_changed and isinstance(data, dict)
                and data.get('wallpaper') == str(wallpaper)
                and type(data.get('expires')) in (int, float) and data['expires'] > time.time()
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
        snapshot = Snapshot(paths, state_dir, link_only=(link,))
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
            adaptive, _ = stage_adaptive_theme(wallpaper, config_dir, mode)
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
                if not config.get('wallpaper', {}).get('enabled', True):
                    changed_backend = True
                    command(['swww', 'img', str(wallpaper), '--transition-type', 'fade', '--transition-duration', '0.3'])
                check_selection()
                atomic_link(link, str(wallpaper))
            if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
                command(['hyprctl', 'reload', 'config-only'])
                errors = command(['hyprctl', 'configerrors'])
                if errors:
                    raise RuntimeError(errors)
            check_selection()
            atomic_write(adaptive_path(state_dir), adaptive)
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
    parser.add_argument('--request-id', default=None, help='Opaque carousel request identifier')
    parser.add_argument('--json', action='store_true', help='Emit one final transaction outcome as JSON')
    args = parser.parse_args()
    home = Path(os.path.expanduser('~'))
    config_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    state_dir = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state')))
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', str(state_dir / 'desktop-wallpaper/runtime')))
    record = {'schema_version': 1, 'request_id': args.request_id or uuid.uuid4().hex,
              'status': 'failed', 'wallpaper': os.path.abspath(os.path.expanduser(
                  args.wallpaper or str(config_dir / 'hypr/current_wallpaper'))),
              'palette_revision': None, 'error_code': 'invalid_wallpaper'}
    try:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', record['request_id']):
            record['error_code'] = 'invalid_request'
            raise ValueError('Request identifier must contain 1–80 letters, digits, underscores or hyphens')
        if (args.json or args.request_id) and not args.apply_wallpaper:
            record['error_code'] = 'invalid_request'
            raise ValueError('Request acknowledgment requires --apply-wallpaper')
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
            if args.apply_wallpaper:
                record['error_code'] = 'transaction_busy'
            acquire_request_lock(lock)
            record['error_code'] = 'apply_failed'
            if args.apply_wallpaper:
                with contextlib.redirect_stdout(sys.stderr) if args.json else contextlib.nullcontext():
                    record['palette_revision'] = apply(wallpaper, config_dir, state_dir, runtime)
                record.update(status='applied', error_code=None)
            else:
                snap = Snapshot([config_dir / name for name in MATUGEN_OUTPUTS]
                                + [state_dir / 'noctalia/settings.toml', adaptive_path(state_dir)], state_dir)
                palette_changed = False
                try:
                    _, config, _, palette_changed, mode = palette_for(wallpaper, config_dir)
                    adaptive, _ = stage_adaptive_theme(wallpaper, config_dir, mode)
                    reload_matugen_palette(config, palette_changed)
                    atomic_write(adaptive_path(state_dir), adaptive)
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
        if isinstance(error, TransactionError):
            record.update(status='rolled_back' if error.rolled_back else 'failed',
                          palette_revision=error.palette_revision,
                          error_code='apply_failed' if error.rolled_back else 'rollback_incomplete')
        print('Wallpaper/theme update failed:', error, file=sys.stderr)
        return 1
    finally:
        if args.json:
            print(json.dumps(record, ensure_ascii=False, sort_keys=True))


if __name__ == '__main__': sys.exit(main())
