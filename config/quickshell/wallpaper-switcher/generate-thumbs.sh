#!/usr/bin/env bash
# Preserve the image ratio: the ribbon decides which part to crop on screen.
set -euo pipefail
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-switcher-thumbs-v3"
WALL_DIR="$HOME/Ảnh/Wallpaper"

install -d -m 700 "$CACHE_DIR"
[[ -d "$WALL_DIR" ]] || exit 0
exec 9>"$CACHE_DIR/generate.lock"
if [[ "${1:-}" == --notify ]]; then
    flock 9
else
    flock -n 9 || exit 0
fi

# Lower CPU and I/O priority so background thumbnailing never starves compositor or UI
renice -n 19 -p $$ >/dev/null 2>&1 || true
ionice -c 3 -p $$ >/dev/null 2>&1 || true

status=0
# Follow file links and a linked library root, but never linked subdirectories.
exec 8< <(find -H "$WALL_DIR" -maxdepth 1 -xtype f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
enumeration_pid=$!
while IFS= read -r -d '' image; do
    name="${image##*/}"
    key=$(printf '%s' "$name" | md5sum)
    thumb="$CACHE_DIR/${key%% *}.jpg"
    record="$thumb.stat"
    # No filenames in the record: stat follows links and preserves nanosecond times.
    fingerprint=$(LC_ALL=C stat -L --printf '%d:%i:%s:%y:%z\n' -- "$image" "$thumb" 2>/dev/null) || fingerprint=""
    if [[ ! -f "$thumb" || ! -s "$thumb" || ! -f "$record" || -z "$fingerprint" ]] \
            || [[ "$(<"$record")" != "$fingerprint" ]]; then
        if ! source_stat=$(LC_ALL=C stat -L --printf '%d:%i:%s:%y:%z' -- "$image"); then
            status=1
            continue
        fi
        temporary=$(mktemp "$CACHE_DIR/.thumbnail-XXXXXX.jpg")
        # Read literal filenames; ImageMagick otherwise expands '%' and wildcard patterns.
        if magick '-[0]' -auto-orient -thumbnail '1000x700>' -quality 85 "$temporary" < "$image" \
                && [[ -s "$temporary" ]] && magick identify -quiet "$temporary" >/dev/null 2>&1 \
                && rm -f -- "$record" \
                && mv -fT -- "$temporary" "$thumb" \
                && output_stat=$(LC_ALL=C stat -L --printf '%d:%i:%s:%y:%z' -- "$thumb") \
                && printf '%s\n%s\n' "$source_stat" "$output_stat" > "$temporary.stat" \
                && mv -f -- "$temporary.stat" "$record"; then
            :
        else
            rm -f -- "$temporary" "$temporary.stat"
            printf 'Không tạo được thumbnail: %s\n' "$image" >&2
            status=1
            continue
        fi
    fi
    if [[ "${1:-}" == --notify ]]; then
        printf '%s\n' "${key%% *}"
    fi
done <&8
wait "$enumeration_pid" || status=1
exit "$status"
