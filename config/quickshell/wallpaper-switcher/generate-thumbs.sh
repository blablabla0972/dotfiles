#!/usr/bin/env bash
# Preserve the image ratio: the ribbon decides which part to crop on screen.
set -euo pipefail
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-switcher-thumbs-v3"
WALL_DIR="$HOME/Ảnh/Wallpaper"

install -d -m 700 "$CACHE_DIR"
[[ -d "$WALL_DIR" ]] || exit 0
exec 9>"$CACHE_DIR/generate.lock"
flock -n 9 || exit 0

# Lower CPU and I/O priority so background thumbnailing never starves compositor or UI
renice -n 19 -p $$ >/dev/null 2>&1 || true
ionice -c 3 -p $$ >/dev/null 2>&1 || true

status=0
exec 8< <(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
enumeration_pid=$!
while IFS= read -r -d '' image; do
    name="${image##*/}"
    key=$(printf '%s' "$name" | md5sum)
    thumb="$CACHE_DIR/${key%% *}.jpg"
    if [[ ! -f "$thumb" || ! -s "$thumb" || "$image" -nt "$thumb" ]]; then
        temporary=$(mktemp "$CACHE_DIR/.thumbnail-XXXXXX.jpg")
        # Read literal filenames; ImageMagick otherwise expands '%' and wildcard patterns.
        if magick '-[0]' -auto-orient -thumbnail '1000x700>' -quality 85 "$temporary" < "$image" \
                && [[ -s "$temporary" ]] && magick identify -quiet "$temporary" >/dev/null 2>&1 \
                && mv -f -- "$temporary" "$thumb"; then
            continue
        else
            rm -f -- "$temporary"
            printf 'Không tạo được thumbnail: %s\n' "$image" >&2
            status=1
        fi
    fi
done <&8
wait "$enumeration_pid" || status=1
exit "$status"
