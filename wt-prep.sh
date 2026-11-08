#!/usr/bin/env bash
# Copy machine-specific (gitignored) files into a worktree so preview/apply works there.
# Usage: ./wt-prep.sh .worktrees/<ten>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
wt="${1:?Usage: ./wt-prep.sh <worktree-path>}"
[ -d "$wt/config/hypr" ] || { echo "worktree khong hop le: $wt" >&2; exit 1; }
if [ "$wt/config/hypr" -ef config/hypr ]; then
    echo 'Khong the chuan bi chinh repo nguon nhu worktree' >&2
    exit 1
fi

# Inspect links without following GPU directory symlinks outside this tree.
inputs=(config/hypr/current_wallpaper config/hypr/gpu)
if [ -d config/hypr/gpu ] && [ ! -L config/hypr/gpu ]; then
    while IFS= read -r -d '' link; do
        inputs+=("$link")
    done < <(find -P config/hypr/gpu -type l -print0)
fi

# Preflight both removals before changing either destination.
python3 - "$wt" "${inputs[@]}" <<'PY'
from collections import deque
import os
from pathlib import Path
import sys


def resolve_checked(path, removals=()):
    # Do not collapse '..' before inspecting preceding symlink components.
    pending = deque(os.path.join(os.getcwd(), path).split('/'))
    resolved = Path('/')
    hops = 0
    while pending:
        part = pending.popleft()
        if part in ('', '.'):
            continue
        if part == '..':
            resolved = resolved.parent
            continue
        candidate = resolved / part
        if any(candidate == root or root in candidate.parents for root in removals):
            raise ValueError(f'repo nguon depends on removed path: {candidate}')
        if candidate.is_symlink():
            hops += 1
            if hops > 40:
                raise ValueError(f'too many symlink hops: {path}')
            target = os.readlink(candidate)
            if os.path.isabs(target):
                resolved = Path('/')
            pending.extendleft(reversed(target.split('/')))
        else:
            resolved = candidate
    return resolved


try:
    removals = []
    for item in ('current_wallpaper', 'gpu'):
        if os.path.lexists(f'config/hypr/{item}'):
            destination = Path(sys.argv[1]) / 'config/hypr' / item
            # Unlinking a destination symlink removes its entry, not its referent.
            removals.append(resolve_checked(str(destination.parent)) / item)
    for source in sys.argv[2:]:
        if os.path.lexists(source):
            referent = resolve_checked(source, removals)
            if os.path.isdir(source) and any(referent in root.parents for root in removals):
                raise ValueError(f'repo nguon contains a removed path: {source}')
except (OSError, ValueError) as error:
    sys.exit(f'Khong the chuan bi worktree: {error}')
PY

# Resolve relative targets while all source inputs are still intact.
relative_links=()
link_targets=()
for input in "${inputs[@]}"; do
    if [ -L "$input" ] && [[ "$(readlink -- "$input")" != /* ]]; then
        relative_links+=("$input")
        link_targets+=("$(realpath -m -- "$input")")
    fi
done

copied=0
if [ -e config/hypr/current_wallpaper ] || [ -L config/hypr/current_wallpaper ]; then
    rm -f "$wt/config/hypr/current_wallpaper"
    cp -a config/hypr/current_wallpaper "$wt/config/hypr/"
    copied=$((copied + 1))
else
    echo "[WARN] config/hypr/current_wallpaper khong ton tai trong repo goc, bo qua" >&2
fi

if [ -e config/hypr/gpu ] || [ -L config/hypr/gpu ]; then
    rm -rf "$wt/config/hypr/gpu"
    cp -a config/hypr/gpu "$wt/config/hypr/"
    copied=$((copied + 1))
else
    echo "[WARN] config/hypr/gpu khong ton tai trong repo goc, bo qua" >&2
fi

for index in "${!relative_links[@]}"; do
    ln -sfn -- "${link_targets[$index]}" "$wt/${relative_links[$index]}"
done

echo "prepped: $wt ($copied/2 machine-specific items)"
