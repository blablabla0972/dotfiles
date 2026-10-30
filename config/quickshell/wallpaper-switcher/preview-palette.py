#!/usr/bin/env python3
"""Read-only Matugen 4.2 preview with stdlib disk caching in XDG_CACHE_HOME."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import NamedTemporaryFile, TemporaryDirectory

SCHEMA_VERSION = 1
CONFIG_CONTENT = '[config.wallpaper]\nset = false\ncommand = ""\n\n[templates]\n'
JSON_FLAGS = ('--dry-run', '--json', 'hex')
FIXED_FLAGS = (
    '--prefer', 'less-saturation', '--source-color-index', '0', '--quiet'
)
SWATCH_RE = re.compile(r'#[0-9a-fA-F]{6}\Z')


def get_cache_dir() -> Path:
    cache_home = os.environ.get('XDG_CACHE_HOME')
    base = Path(cache_home).expanduser() if cache_home else Path.home() / '.cache'
    return base / 'wallpaper-switcher' / 'previews-v1'


def get_matugen_identity():
    binary = shutil.which('matugen')
    if not binary:
        return None
    try:
        real_path = os.path.realpath(binary)
        st = os.stat(real_path)
        stat_id = f'{st.st_dev}:{st.st_ino}:{st.st_size}:{st.st_mtime_ns}:{st.st_ctime_ns}'
        return real_path, stat_id
    except OSError:
        return None


def compute_image_sha256(path: Path) -> str:
    with open(path, 'rb') as f:
        if hasattr(hashlib, 'file_digest'):
            return hashlib.file_digest(f, 'sha256').hexdigest()
        hasher = hashlib.sha256()
        while chunk := f.read(65536):
            hasher.update(chunk)
        return hasher.hexdigest()


def compute_cache_key(image_hash: str, mode: str, real_path: str, stat_id: str) -> str:
    identity = [SCHEMA_VERSION, real_path, stat_id, CONFIG_CONTENT,
                JSON_FLAGS, FIXED_FLAGS, mode, image_hash]
    return hashlib.sha256(json.dumps(identity).encode()).hexdigest()


def validate_swatches(swatches):
    if not isinstance(swatches, (list, tuple)) or len(swatches) != 5:
        return False
    return all(isinstance(color, str) and bool(SWATCH_RE.fullmatch(color)) for color in swatches)


def read_cached_swatches(cache_path: Path):
    try:
        if cache_path.stat().st_size > 4096:
            return None
        data = json.loads(cache_path.read_text(encoding='utf-8'))
        if not isinstance(data, dict) or data.get('schema_version') != SCHEMA_VERSION:
            return None
        swatches = data.get('swatches')
        if validate_swatches(swatches):
            return list(swatches)
    except (OSError, ValueError, TypeError, KeyError):
        pass
    return None


def write_cached_swatches(cache_path: Path, swatches: list) -> None:
    try:
        target_dir = cache_path.parent
        target_dir.mkdir(parents=True, exist_ok=True)
        tmp = NamedTemporaryFile(
            mode='w',
            dir=target_dir,
            prefix='preview-cache-',
            suffix='.tmp',
            delete=False,
            encoding='utf-8',
        )
        try:
            json.dump({'schema_version': SCHEMA_VERSION, 'swatches': swatches}, tmp, separators=(',', ':'))
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp.close()
            os.replace(tmp.name, cache_path)
        except Exception:
            try:
                tmp.close()
            except Exception:
                pass
            if os.path.exists(tmp.name):
                try:
                    os.unlink(tmp.name)
                except OSError:
                    pass
            raise
    except (OSError, ValueError):
        pass


def preview(wallpaper, mode, request_id):
    wallpaper = os.path.abspath(os.path.expanduser(wallpaper))
    if not request_id or mode not in ('dark', 'light') or not Path(wallpaper).is_file():
        raise ValueError('Invalid preview request')

    matugen_info = get_matugen_identity()
    cache_path = None
    if matugen_info is not None:
        real_path, stat_id = matugen_info
        try:
            image_hash = compute_image_sha256(Path(wallpaper))
            cache_key = compute_cache_key(image_hash, mode, real_path, stat_id)
            cache_path = get_cache_dir() / f'{cache_key}.json'
            cached = read_cached_swatches(cache_path)
            if cached is not None:
                return dict(schema_version=1, request_id=request_id, wallpaper=wallpaper,
                            mode=mode, swatches=cached)
        except OSError:
            cache_path = None

    with TemporaryDirectory(prefix='wallpaper-preview-') as directory:
        config = Path(directory) / 'config.toml'
        config.write_text(CONFIG_CONTENT)
        env = dict(os.environ, XDG_CONFIG_HOME=directory, XDG_CACHE_HOME=directory,
                   XDG_STATE_HOME=directory)
        result = subprocess.run(
            ['matugen', 'image', wallpaper, '--config', str(config), *JSON_FLAGS,
             '--mode', mode, *FIXED_FLAGS],
            capture_output=True, text=True, check=True, timeout=8, cwd=directory, env=env,
        )
        colors = json.loads(result.stdout)['colors']
        swatches = [colors[role][mode]['color']
                    for role in ('primary', 'secondary', 'tertiary', 'surface', 'on_surface')]
        if not validate_swatches(swatches):
            raise ValueError('Invalid Matugen preview colors')

    if cache_path is not None:
        try:
            if (compute_image_sha256(Path(wallpaper)) == image_hash
                    and get_matugen_identity() == matugen_info):
                write_cached_swatches(cache_path, swatches)
        except OSError:
            pass

    return dict(schema_version=1, request_id=request_id, wallpaper=wallpaper,
                mode=mode, swatches=swatches)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request-id', required=True)
    parser.add_argument('--mode', choices=('dark', 'light'), required=True)
    parser.add_argument('wallpaper')
    args = parser.parse_args()
    try:
        result = preview(args.wallpaper, args.mode, args.request_id)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'Palette preview unavailable: {error}', file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
