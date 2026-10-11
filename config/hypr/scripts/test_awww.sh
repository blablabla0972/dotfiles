#!/bin/bash
start=$(date +%s%3N)
awww img "$HOME/Ảnh/Wallpaper/wallhaven-zpvdzv.jpg" --transition-type grow --transition-duration 0.8 > /dev/null
end=$(date +%s%3N)
echo "awww returned in $((end - start)) ms, but transition is 800 ms"
