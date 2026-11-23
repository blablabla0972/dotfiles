#!/usr/bin/env bash
set -euo pipefail

# Prevent overlapping screenshot sessions (including repeated Print presses).
exec 9>"${XDG_RUNTIME_DIR:?}/hypr-screenshot-region.lock"
flock -n 9 || exit 0

for command in hyprpicker hyprctl jq slurp grim satty xdg-user-dir wl-copy; do
    if ! command -v "$command" >/dev/null; then
        notify-send "Ảnh chụp màn hình" "Thiếu lệnh $command."
        exit 1
    fi
done

tmp=$(mktemp -d "${XDG_RUNTIME_DIR}/hypr-screenshot.XXXXXX")
picker=
selector=
cleanup() {
    if [[ -n $selector ]]; then
        kill "$selector" 2>/dev/null || true
        wait "$selector" 2>/dev/null || true
    fi
    if [[ -n $picker ]]; then
        kill "$picker" 2>/dev/null || true
        wait "$picker" 2>/dev/null || true
    fi
    rm -rf -- "$tmp"
}
trap cleanup EXIT
trap "exit 130" INT
trap "exit 143" TERM HUP

# Freeze every output before starting the region selector.
hyprpicker -r -z -d >/dev/null 2>&1 &
picker=$!
ready=false
for ((i = 0; i < 40; i++)); do
    kill -0 "$picker" 2>/dev/null || exit 1
    if hyprctl -j layers | jq -e --argjson pid "$picker" \
        'length > 0 and all(.[]; any(.levels[][]; .pid == $pid and .namespace == "hyprpicker" and .alpha >= 0.99))' >/dev/null; then
        ready=true
        break
    fi
    sleep 0.025
done
[[ $ready == true ]] || exit 1
# A mapped layer can precede its first committed image buffer.
sleep 0.08

# Escape cancels without changing the clipboard.
slurp -b '#18161188' -s '#e6c57222' -c '#e6c572ff' -w 2 > "$tmp/geometry" &
selector=$!
wait "$selector" || exit 0
selector=
read -r geometry < "$tmp/geometry" || exit 0
[[ -n $geometry ]] || exit 0
# Let the compositor remove the selector before capturing the frozen layer.
sleep 0.03

# Capture the frozen layer, not the live desktop or the selection overlay.
kill -0 "$picker" 2>/dev/null || exit 1
grim -g "$geometry" "$tmp/region.png"
kill -0 "$picker" 2>/dev/null || exit 1
kill "$picker" 2>/dev/null || true
wait "$picker" 2>/dev/null || true
picker=

# Keep the clipboard unchanged until Copy; Escape discards the temporary image.
pictures=$(xdg-user-dir PICTURES)
mkdir -p -- "$pictures/Screenshots"
GTK_THEME=Adwaita:dark satty --config /dev/null --filename "$tmp/region.png" \
    --output-filename "$pictures/Screenshots/Screenshot-%Y-%m-%d_%H-%M-%S-%f.png" \
    --app-id local.screenshot.Editor --title "Chỉnh sửa ảnh chụp" \
    --initial-tool pointer --early-exit all \
    --copy-command "wl-copy --type image/png" \
    --actions-on-enter save-to-clipboard --actions-on-escape exit 9>&-
