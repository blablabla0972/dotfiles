#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || $1 != --request-id || -z $2 || -z $3 ]]; then
    echo 'Usage: apply-wallpaper.sh --request-id <id> <wallpaper>' >&2
    exit 2
fi
request_id=$2
wallpaper=$3
script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/generate-theme.py"

# Only the transaction owner emits stdout (one JSON result). Keep diagnostics separate.
errors=$(mktemp)
trap 'rm -f -- "$errors"' EXIT
status=0
python3 "$script" --apply-wallpaper --request-id "$request_id" --json "$wallpaper" 2>"$errors" || status=$?
cat -- "$errors" >&2
if (( status != 0 )); then
    if command -v notify-send >/dev/null 2>&1; then
        last_line=$(tail -n 1 -- "$errors")
        notify-send -u critical -a "Wallpaper Switcher" -- "Lỗi đổi hình nền" \
            "Không thể áp dụng: ${wallpaper##*/} — ${last_line:-Transaction exited with status $status}" >/dev/null 2>&1 || true
    fi
fi
exit "$status"
