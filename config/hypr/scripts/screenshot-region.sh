#!/usr/bin/env bash
set -euo pipefail

# Prevent overlapping screenshot sessions (including repeated Print presses).
exec 9>"${XDG_RUNTIME_DIR:?}/hypr-screenshot-region.lock"
flock -n 9 || exit 0

fail() {
    notify-send "Screenshot" "$1" 2>/dev/null || true
    exit 1
}

for command in hyprpicker hyprctl jq slurp grim satty xdg-user-dir; do
    command -v "$command" >/dev/null || fail "Missing required command: $command"
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
    kill -0 "$picker" 2>/dev/null || fail "hyprpicker stopped before the screen was frozen."
    if hyprctl -j layers | jq -e --argjson pid "$picker" \
        'length > 0 and all(.[]; any(.levels[][]; .pid == $pid and .namespace == "hyprpicker" and .alpha >= 0.99))' >/dev/null; then
        ready=true
        break
    fi
    sleep 0.025
done
[[ $ready == true ]] || fail "Timed out waiting for the frozen screen."
# A mapped layer can precede its first committed image buffer.
sleep 0.08

# Escape cancels without changing the clipboard.
slurp > "$tmp/geometry" &
selector=$!
wait "$selector" || exit 0
selector=
read -r geometry < "$tmp/geometry" || exit 0
[[ -n $geometry ]] || exit 0
# Let the compositor remove the selector before capturing the frozen layer.
sleep 0.03

# Capture the frozen layer, not the live desktop or the selection overlay.
kill -0 "$picker" 2>/dev/null || fail "The frozen screen ended before capture."
grim -g "$geometry" "$tmp/region.png" || fail "Could not capture the selected region."
kill -0 "$picker" 2>/dev/null || fail "The frozen screen ended during capture."
kill "$picker" 2>/dev/null || true
wait "$picker" 2>/dev/null || true
picker=

# Keep the clipboard unchanged until Copy; Escape discards the temporary image.
pictures=$(xdg-user-dir PICTURES) || fail "Could not locate the Pictures folder."
mkdir -p -- "$pictures/Screenshots" || fail "Could not create the Screenshots folder."
satty --config /dev/null --filename "$tmp/region.png" \
    --output-filename "$pictures/Screenshots/Screenshot-%Y-%m-%d_%H-%M-%S-%f.png" \
    --app-id local.screenshot.Editor --initial-tool arrow --early-exit all \
    --copy-command "wl-copy --type image/png" \
    --actions-on-enter save-to-clipboard --actions-on-escape exit 9>&-
