#!/usr/bin/env bash

# Rofi App Launcher (binnewbs / Bintang M style)
# Toggle behavior: if rofi is already running, kill it; otherwise launch it.
if pgrep -x rofi >/dev/null; then
    pkill -x rofi
    exit 0
fi

# Ensure pre-cached wallpaper thumbnail exists for instant loading
WALLPAPER="$(readlink -f "$HOME/.config/hypr/current_wallpaper" 2>/dev/null)"
THUMB="$HOME/.config/rofi/wallpaper_thumb.jpg"

if [ -f "$WALLPAPER" ]; then
    if [ ! -f "$THUMB" ]; then
        magick "$WALLPAPER" -resize "1000x1000>" -quality 85 "$THUMB"
    elif [ "$WALLPAPER" -nt "$THUMB" ]; then
        # Update thumbnail in background if wallpaper is newer
        (magick "$WALLPAPER" -resize "1000x1000>" -quality 85 "$THUMB") &
    fi
fi

rofi -show drun -config "$HOME/.config/rofi/config.rasi"
