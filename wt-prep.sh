#!/usr/bin/env bash
# Copy machine-specific (gitignored) files into a worktree so preview/apply works there.
# Usage: ./wt-prep.sh .worktrees/<ten>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
wt="${1:?Usage: ./wt-prep.sh <worktree-path>}"
[ -d "$wt/config/hypr" ] || { echo "worktree khong hop le: $wt" >&2; exit 1; }

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

echo "prepped: $wt ($copied/2 machine-specific items)"
