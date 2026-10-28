#!/usr/bin/env bash
# Run from the user's Hyprland terminal; default is a read-only installation plan.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
main="$(dirname "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)")"
components=(hypr noctalia quickshell matugen rice kitty alacritty gtk-3.0 gtk-4.0 qt5ct qt6ct btop kdeglobals)

rollback() {
    # Restore only the validated directory/file symlinks, never state/bin/prompt.
    # Main's old installer has no --no-state option and its default scope is wider.
    python3 - "$main" "$repo" "${components[@]}" <<'PY' || return
import os, sys
from pathlib import Path
main, repo = map(Path, sys.argv[1:3])
for name in sys.argv[3:]:
    destination = Path.home() / '.config' / name
    if name == 'rice':
        if destination.is_symlink() and destination.resolve() == repo / 'config/rice':
            destination.unlink()
        continue
    source = main / ('root' if name == 'kdeglobals' else 'config') / name
    temporary = destination.with_name(f'.{name}.quiet-rollback-{os.getpid()}')
    try:
        temporary.symlink_to(source)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
PY
    hyprctl reload config-only || return
    noctalia msg config-reload || return
    noctalia msg color-palette-reload || return
    local errors
    errors="$(hyprctl configerrors)" || return
    [[ -z "$errors" ]] || { printf '%s\n' "$errors" >&2; return 1; }
}

case "${1:---dry-run}" in
    --dry-run)
        (cd "$repo" && bash ./install.sh --dry-run --no-state "${components[@]}")
        ;;
    --apply|--rollback)
        [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || { echo 'Run this in a terminal inside your Hyprland session.' >&2; exit 1; }
        [[ "$repo" != "$main" ]] || { echo 'Use the isolated quiet-current worktree.' >&2; exit 1; }
        [[ "$(git -C "$main" rev-parse HEAD)" == 6b832a8c0e85377b1617b2d474dd6db82df3a851 ]] || {
            echo 'Main has advanced; inspect its changes before using this pre-merge preview.' >&2; exit 1;
        }
        # Never replace a real directory or another worktree's configuration.
        for name in "${components[@]}"; do
            target="$HOME/.config/$name"
            [[ "$name" == rice && ! -e "$target" && ! -L "$target" ]] && continue
            source="config/$name"
            [[ "$name" == kdeglobals ]] && source="root/$name"
            [[ -L "$target" && ( "$(readlink -f "$target")" == "$main/$source" || "$(readlink -f "$target")" == "$repo/$source" ) ]] || {
                echo "Preserving unexpected configuration: $target" >&2; exit 1;
            }
        done
        if [[ "$1" == --rollback ]]; then rollback; exit; fi
        wallpaper="$(readlink -f "$HOME/.config/hypr/current_wallpaper")"
        [[ -f "$wallpaper" ]] || { echo 'Current wallpaper is missing.' >&2; exit 1; }
        errors="$(hyprctl configerrors)"
        [[ -z "$errors" ]] || { printf '%s\n' "$errors" >&2; exit 1; }
        noctalia config validate "$repo/config/noctalia/config.toml"
        umask 077
        evidence="${XDG_STATE_HOME:-$HOME/.local/state}/quiet-current-validation"
        mkdir -p "$evidence"
        # Every generated theme target follows the worktree before the owner writes.
        trap 'trap - ERR; echo "Preview failed; restoring main configuration." >&2; rollback || echo "Manual recovery required: see installer backups." >&2; exit 1' ERR
        (cd "$repo" && bash ./install.sh --no-state "${components[@]}")
        noctalia msg config-reload
        python3 "$repo/config/hypr/scripts/generate-theme.py" --apply-wallpaper \
            --request-id "quiet-preview-$(date +%s)" --json "$wallpaper" > "$evidence/apply-result.json"
        noctalia config export full > "$evidence/effective-config.toml"
        errors="$(hyprctl configerrors)"
        [[ -z "$errors" ]] || { printf '%s\n' "$errors" >&2; false; }
        if command -v grim >/dev/null 2>&1; then grim "$evidence/after.png"; fi
        trap - ERR
        echo "Preview applied. Evidence: $evidence"
        echo "Inspect SUPER+SPACE and SUPER+W; merge remains pending your visual acceptance."
        ;;
    *) echo 'Usage: bash preview-quiet-current.sh [--dry-run|--apply|--rollback]' >&2; exit 2 ;;
esac
