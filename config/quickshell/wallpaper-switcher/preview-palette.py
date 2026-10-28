#!/usr/bin/env python3
"""Read-only Matugen 4.2 preview; all configuration and caches are disposable."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory


def preview(wallpaper, mode, request_id):
    wallpaper = os.path.abspath(os.path.expanduser(wallpaper))
    if not request_id or mode not in ('dark', 'light') or not Path(wallpaper).is_file():
        raise ValueError('Invalid preview request')
    with TemporaryDirectory(prefix='wallpaper-preview-') as directory:
        config = Path(directory) / 'config.toml'
        # 4.2 requires these empty fields even when no templates or command are used.
        config.write_text('[config.wallpaper]\nset = false\ncommand = ""\n\n[templates]\n')
        env = dict(os.environ, XDG_CONFIG_HOME=directory, XDG_CACHE_HOME=directory,
                   XDG_STATE_HOME=directory)
        result = subprocess.run(
            ['matugen', 'image', wallpaper, '--config', str(config), '--dry-run', '--json', 'hex',
             '--mode', mode, '--prefer', 'less-saturation', '--source-color-index', '0', '--quiet'],
            capture_output=True, text=True, check=True, timeout=8, cwd=directory, env=env,
        )
        colors = json.loads(result.stdout)['colors']
        swatches = [colors[role][mode]['color']
                    for role in ('primary', 'secondary', 'tertiary', 'surface', 'on_surface')]
        if any(not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color)
               for color in swatches):
            raise ValueError('Invalid Matugen preview colors')
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
