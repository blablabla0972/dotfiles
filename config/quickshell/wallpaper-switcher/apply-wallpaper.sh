#!/usr/bin/env bash
set -euo pipefail

wallpaper="${1:?Wallpaper path required}"
script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/generate-theme.py"

# Serialize, validate, apply and verify in one foreground transaction.
# Noctalia remains the palette generator; awww remains the wallpaper backend.
if ! err_msg=$(python3 "$script" --apply-wallpaper "$wallpaper" 2>&1); then
    echo "$err_msg" >&2
    if command -v notify-send >/dev/null 2>&1; then
        last_line=$(echo "$err_msg" | grep -v '^$' | tail -n 1)
        notify-send -u critical -a "Wallpaper Switcher" "Lỗi đổi hình nền" "Không thể áp dụng: $(basename "$wallpaper")\n$last_line"
    fi
    exit 1
fi
