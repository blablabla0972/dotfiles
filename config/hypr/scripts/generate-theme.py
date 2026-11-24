#!/usr/bin/env python3
"""Generate the Matugen palette and synchronize desktop theme outputs."""
import argparse
import configparser
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import json
import math
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


MATUGEN_OUTPUTS = ('hypr/colors.conf', 'rice/theme/matugen.json', 'micro/colorschemes/adaptive.micro')
MATUGEN_QUICKSHELL_OUTPUTS = ('kitty/themes/rice.conf', 'alacritty/themes/rice.toml',
    'gtk-3.0/gtk.css', 'gtk-4.0/gtk.css', 'qt5ct/colors/rice.conf',
    'qt6ct/colors/rice.conf', 'btop/themes/rice.theme')
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
    palette = (config_dir / 'rice/theme/matugen.json').read_bytes()
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


def transition_fps():
    """Use the fastest active output; IPC failure must not abort a transaction."""
    try:
        monitors = json.loads(command(['hyprctl', 'monitors', '-j'], timeout=2))
        rates = [monitor.get('refreshRate') for monitor in monitors
                 if isinstance(monitor, dict) and not monitor.get('disabled', False)
                 and monitor.get('dpmsStatus', True)]
        rates = [rate for rate in rates if isinstance(rate, (int, float))
                 and not isinstance(rate, bool) and math.isfinite(rate) and rate > 0]
        return max(1, min(65535, round(max(rates, default=60))))
    except (RuntimeError, OSError, TypeError, ValueError, subprocess.TimeoutExpired):
        return 60


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
            # Detect edits restored to the same bytes and mtime before rendering ends.
            stamp = os.fstat(stream.fileno())
            hashes.append((str(path), stamp.st_dev, stamp.st_ino, stamp.st_size,
                           stamp.st_mtime_ns, stamp.st_ctime_ns,
                           hashlib.file_digest(stream, 'sha256').hexdigest()))
    identity = [2, mode, MATUGEN_FLAGS,
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


def configured_matugen_outputs(config_dir):
    """Resolve every configured Matugen output so transaction backups stay complete."""
    source = config_dir / 'matugen/config.toml'
    settings = tomllib.loads(source.read_text()) if source.is_file() else {}
    home_config = Path.home() / '.config'
    outputs = set(MATUGEN_OUTPUTS + MATUGEN_QUICKSHELL_OUTPUTS)
    for template in settings.get('templates', {}).values():
        output = template.get('output_path')
        if not output:
            continue
        output_path = Path(output).expanduser()
        if output_path.is_relative_to(home_config):
            output_path = config_dir / output_path.relative_to(home_config)
        elif not output_path.is_absolute():
            output_path = source.parent / output_path
        output_path = Path(os.path.abspath(output_path))
        try:
            outputs.add(str(output_path.relative_to(config_dir)))
        except ValueError:
            raise RuntimeError('Matugen outputs must stay inside the managed config directory')
    return tuple(sorted(outputs))


def render_matugen(wallpaper, config_dir, mode, backend=None):
    source = config_dir / 'matugen/config.toml'
    settings = tomllib.loads(source.read_text())
    wallpaper_options = settings.get('config', {}).get('wallpaper')
    if wallpaper_options is not None and wallpaper_options.get('set', True):
        raise RuntimeError('Matugen wallpaper changes bypass the transaction; set config.wallpaper.set=false')
    home_config = Path.home() / '.config'
    output_names = configured_matugen_outputs(config_dir)
    outputs = {config_dir / name for name in output_names}
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
            if key == 'input_path':
                path = path.resolve()
            if key == 'output_path' and path not in outputs:
                raise RuntimeError('Additional Matugen outputs need backup paths before theme generation')
            template[key] = str(path)
    names = {name for name in output_names if any(
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


_CURRENT_MODE = None


def detect_backend(backend_opt=None):
    return 'quickshell'


def generate_hyprland_lua(palette_json, mode):
    p = palette_json.get(mode, {})
    def rgb(hex_code):
        return f'rgb({hex_code.lstrip("#")})'
    primary = rgb(p.get("mPrimary", "#e4c36c"))
    surface = rgb(p.get("mSurface", "#16130b"))
    on_surface = rgb(p.get("mOnSurface", "#eae1d4"))
    secondary = rgb(p.get("mSecondary", "#d5c5a0"))
    on_secondary = rgb(p.get("mOnSecondary", "#392f15"))
    error = rgb(p.get("mError", "#ffb4ab"))
    on_error = rgb(p.get("mOnError", "#690005"))

    return f"""-- Generated by theme generator (Quickshell mode)

local primary = "{primary}"
local surface = "{surface}"
local on_surface = "{on_surface}"
local secondary = "{secondary}"
local on_secondary = "{on_secondary}"
local error = "{error}"
local on_error = "{on_error}"

local function apply_theme()
    hl.config({{
        general = {{
            col = {{
                active_border = primary,
                inactive_border = surface,
            }},
        }},
        group = {{
            col = {{
                border_active = secondary,
                border_inactive = surface,
                border_locked_active = error,
                border_locked_inactive = surface,
            }},

            groupbar = {{
                col = {{
                    active = secondary,
                    inactive = surface,
                    locked_active = error,
                    locked_inactive = surface,
                }},
                text_color = on_secondary,
                text_color_inactive = on_surface,
                text_color_locked_active = on_error,
                text_color_locked_inactive = on_surface,
            }},
        }},
    }})
end

return {{
    colors = {{
        primary = primary,
        surface = surface,
        on_surface = on_surface,
        secondary = secondary,
        on_secondary = on_secondary,
        error = error,
        on_error = on_error,
    }},
    apply_theme = apply_theme
}}
"""


def palette_for(wallpaper, config_dir, backend=None, target_mode=None):
    mode = target_mode or _CURRENT_MODE
    if mode not in {'dark', 'light'}:
        if shutil.which('gsettings'):
            try:
                scheme = command(['gsettings', 'get', 'org.gnome.desktop.interface', 'color-scheme'])
                if 'prefer-light' in scheme:
                    mode = 'light'
                elif 'prefer-dark' in scheme:
                    mode = 'dark'
            except Exception:
                pass
    if mode not in {'dark', 'light'}:
        state_dir = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
        ad_file = adaptive_path(state_dir)
        if ad_file.is_file():
            try:
                data = json.loads(ad_file.read_text())
                mode = data.get('mode')
            except Exception:
                pass
    if mode not in {'dark', 'light'}:
        mode = 'dark'

    palette_path = config_dir / 'rice/theme/matugen.json'
    previous_palette = palette_path.read_bytes() if palette_path.is_file() else None
    render_matugen(wallpaper, config_dir, mode)

    try:
        palette_json = json.loads(palette_path.read_text())
    except (OSError, ValueError):
        palette_json = {}

    if isinstance(palette_json, dict) and all(isinstance(palette_json.get(k), dict) for k in ('dark', 'light')):
        lua_code = generate_hyprland_lua(palette_json, mode)
        atomic_write(config_dir / 'hypr/rice-theme.lua', lua_code.encode())

    changed = previous_palette != (palette_path.read_bytes() if palette_path.is_file() else None)
    config = {'theme': {'source': 'wallpaper', 'matugen_palette': 'matugen', 'mode': mode}}
    return palette_json, config, [], changed, mode



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
        if app.startswith('qt'):
            ini[section]['custom_palette'] = 'true'
            ini[section]['color_scheme_path'] = str(config_dir / app / 'colors/rice.conf')
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


def theme_snapshot_paths(config_dir, state_dir):
    names = ['hypr/current_wallpaper', 'hypr/rice-theme.lua', 'hypr/hyprland.lua',
             'kitty/kitty.conf', 'alacritty/alacritty.toml', 'btop/btop.conf',
             'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini', 'gtk-4.0/gtk-dark.css',
             'qt5ct/qt5ct.conf', 'qt6ct/qt6ct.conf', 'kdeglobals']
    outputs = configured_matugen_outputs(config_dir)
    return [config_dir / p for p in (*names, *outputs)] + [adaptive_path(state_dir)]


def reload_compositor():
    if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or shutil.which('hyprctl'):
        command(['hyprctl', 'reload', 'config-only'])
        errors = command(['hyprctl', 'configerrors'])
        if errors:
            raise RuntimeError(errors)


def apply(wallpaper, config_dir, state_dir, runtime, backend='quickshell', target_mode=None):
    global _CURRENT_MODE
    _CURRENT_MODE = target_mode
    link = config_dir / 'hypr/current_wallpaper'
    old_wallpaper = link.resolve() if link.exists() else None
    snapshot = Snapshot(theme_snapshot_paths(config_dir, state_dir), state_dir, link_only=(link,))
    palette_path = config_dir / 'rice/theme/matugen.json'
    previous_revision = hashlib.sha256(palette_path.read_bytes()).hexdigest() if palette_path.is_file() else None
    changed_backend = False
    try:
        changed_backend = True
        duration_sec = 1.8
        command(['swww', 'img', str(wallpaper), '--transition-type', 'grow', '--transition-pos', 'center',
                 '--transition-fps', str(transition_fps()), '--transition-duration', str(duration_sec), '--transition-bezier', '.54,0,.34,.99'])
        deadline = time.monotonic() + duration_sec + 0.05
        _, _, _, _, mode = palette_for(wallpaper, config_dir, target_mode=target_mode)
        adaptive, revision = stage_adaptive_theme(wallpaper, config_dir, mode)
        now = time.monotonic()
        if now < deadline:
            time.sleep(deadline - now)
        sync_toolkit_settings(config_dir, mode)
        reload_compositor()
        atomic_link(link, str(wallpaper))
        atomic_write(adaptive_path(state_dir), adaptive)
        print('WALLPAPER_AND_THEME_OK', wallpaper, '\nBACKUP', snapshot.directory)
        return revision
    except Exception as cause:
        restored = False
        try:
            snapshot.restore()
            if changed_backend:
                if not old_wallpaper or not old_wallpaper.is_file():
                    raise RuntimeError('Previous wallpaper is unknown; backend recovery cannot be verified')
                command(['swww', 'img', str(old_wallpaper), '--transition-type', 'none'])
            reload_compositor()
            restored = True
        except Exception as error:
            print(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}', file=sys.stderr)
        if restored:
            print('RESTORED_SNAPSHOT', snapshot.directory, file=sys.stderr)
        raise TransactionError(str(cause), restored, previous_revision) from cause


def wallpaper_changed(config_dir, state_dir, runtime, mode_changed=False, backend='quickshell', target_mode=None):
    global _CURRENT_MODE
    _CURRENT_MODE = target_mode
    link = config_dir / 'hypr/current_wallpaper'
    wallpaper = link.resolve(strict=True)
    if not wallpaper.is_file():
        raise ValueError('Wallpaper path is invalid')
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'rice-wallpaper-apply.lock').open('a') as lock:
        acquire_request_lock(lock)
        snapshot = Snapshot(theme_snapshot_paths(config_dir, state_dir), state_dir, link_only=(link,))
        try:
            _, _, _, _, mode = palette_for(wallpaper, config_dir, target_mode=target_mode)
            adaptive, _ = stage_adaptive_theme(wallpaper, config_dir, mode)
            sync_toolkit_settings(config_dir, mode)
            reload_compositor()
            atomic_write(adaptive_path(state_dir), adaptive)
        except Exception:
            try:
                snapshot.restore()
                reload_compositor()
            except Exception as error:
                print(f'Rollback incomplete; snapshot retained at {snapshot.directory}: {error}', file=sys.stderr)
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
    parser.add_argument('--backend', choices=['auto', 'quickshell'], default='quickshell',
                        help='Desktop shell backend for theme synchronization')
    parser.add_argument('--mode', choices=['dark', 'light'], default=None,
                        help='Target theme mode (dark or light)')
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
        backend = detect_backend(args.backend)
        if args.wallpaper_changed or args.theme_mode_changed:
            wallpaper_changed(config_dir, state_dir, runtime, mode_changed=args.theme_mode_changed, backend=backend, target_mode=args.mode)
            return 0
        wallpaper = Path(args.wallpaper) if args.wallpaper else config_dir / 'hypr/current_wallpaper'
        wallpaper = wallpaper.expanduser().resolve(strict=True)
        if not wallpaper.is_file() or '\n' in str(wallpaper) or '\r' in str(wallpaper):
            raise ValueError('Wallpaper must be a regular image file with a single-line path')
        runtime.mkdir(parents=True, exist_ok=True)
        with (runtime / 'rice-wallpaper-apply.lock').open('a') as lock:
            if args.apply_wallpaper:
                record['error_code'] = 'transaction_busy'
            acquire_request_lock(lock)
            record['error_code'] = 'apply_failed'
            if args.apply_wallpaper:
                with contextlib.redirect_stdout(sys.stderr) if args.json else contextlib.nullcontext():
                    record['palette_revision'] = apply(wallpaper, config_dir, state_dir, runtime, backend=backend, target_mode=args.mode)
                record.update(status='applied', error_code=None)
            else:
                snap = Snapshot(theme_snapshot_paths(config_dir, state_dir), state_dir, link_only=(config_dir / 'hypr/current_wallpaper',))
                try:
                    _, _, _, _, mode = palette_for(wallpaper, config_dir, target_mode=args.mode)
                    adaptive, _ = stage_adaptive_theme(wallpaper, config_dir, mode)
                    atomic_write(adaptive_path(state_dir), adaptive)
                except Exception:
                    snap.restore()
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

