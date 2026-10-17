#!/usr/bin/env bash
# Copy machine-specific (gitignored) files into a worktree so preview/apply works there.
# Usage: ./wt-prep.sh .worktrees/<ten>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
wt="${1:?Usage: ./wt-prep.sh <worktree-path>}"
[ -d "$wt/config/hypr" ] || { echo "worktree khong hop le: $wt"; exit 1; }
rm -f  "$wt/config/hypr/current_wallpaper"
rm -rf "$wt/config/hypr/gpu"
cp -a config/hypr/current_wallpaper "$wt/config/hypr/"
cp -a config/hypr/gpu "$wt/config/hypr/"
echo "prepped: $wt (current_wallpaper, gpu)"
