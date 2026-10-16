# Dotfiles — CachyOS + Hyprland

Bản lưu cấu hình hệ sinh thái Hyprland trên máy `admin` (CachyOS, Hyprland 0.56.2).

## Cấu trúc

```
dotfiles/
├── config/          # symlink → ~/.config/<tên>
│   ├── hypr/        # Hyprland (backend Lua), hyprlock, scripts
│   ├── noctalia/    # Bar/shell Noctalia (thay waybar + dunst + swww UI)
│   ├── matugen/     # Sinh màu từ wallpaper
│   ├── rofi/        # Launcher
│   ├── quickshell/  # 3D Wallpaper Carousel
│   ├── btop/        # System monitor
│   ├── fish/        # Shell fish
│   ├── alacritty/ kitty/   # Terminal
│   ├── gtk-3.0/ gtk-4.0/   # GTK theme
│   ├── qt5ct/ qt6ct/       # Qt theme
│   ├── fcitx5/      # Input method (Bamboo)
│   ├── systemd/     # User units (swww-daemon)
│   ├── uwsm/ menus/ xkb/ xed/ xsettingsd/ cachyos/
│   └── micro/       # Editor (settings + colorschemes)
├── root/            # symlink → ~/.config/<tên-file>
│   ├── *-flags.conf # Chromium/Electron flags
│   ├── kdeglobals dolphinrc mimeapps.list
│   └── locale.conf user-dirs.dirs user-dirs.locale
└── state/           # symlink → ~/.local/state/<tên-app>/ (vd: noctalia/settings.toml)
```

## Cài đặt trên máy mới

```bash
git clone git@github.com:<user>/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run   # xem trước
./install.sh             # cài hết (backup file cũ vào ~/.config/backups/dotfiles-<timestamp>/)
./install.sh hypr rofi   # chỉ cài vài mục
```

## Đồng bộ sau khi sửa cấu hình

```bash
cd ~/Projects/dotfiles
rsync -a --delete --exclude={'*.bak','*.bak-*','*.bak.*','*.backup-*','__pycache__','*.pyc','current_wallpaper','gpu','backup','backup_baseline','wallpaper_thumb.jpg'} \
  ~/.config/hypr/ config/hypr/
git add -A && git commit -m "update: mô tả thay đổi"
```

## Lưu ý khi dùng trên máy khác

Các symlink sau là machine-specific, không hoạt động ở máy khác — cần tạo lại:

- `config/hypr/current_wallpaper` → một ảnh trong `~/Ảnh/Wallpaper`
- `config/hypr/gpu/{intel,nvidia}` → `/dev/dri/by-path/...` (theo PCI của máy)

Các đường dẫn `/home/admin/...` trong config (fish PATH, systemd service, noctalia hook)
cũng cần đổi sang `$HOME` hoặc user mới nếu máy khác tên user khác.

## Hệ sinh thái đang dùng

| Thành phần | Vai trò |
|---|---|
| Hyprland 0.56.2 | Compositor, config backend **Lua** (`hyprland.lua` load 12 module trong `config/`) |
| Noctalia | Bar + notification + control center (thay waybar/dunst/swaync) |
| swww | Wallpaper daemon (chạy qua systemd user unit) |
| matugen | Sinh màu từ wallpaper → `hypr/colors.conf`, `rofi/colors.rasi` |
| Rofi | App launcher (`SUPER+SPACE`) |
| hyprlock | Màn hình khóa |
| fcitx5 + Bamboo | Nhập tiếng Việt |

## Workflow rice với worktree (từ 2026-10-16)

5 mục rice đã cài bằng `./install.sh` — **live là symlink vào repo** (nhánh `main`):
`~/.config/{hypr,noctalia,quickshell,matugen,rofi}` → `config/*`.
Sửa trong `config/` của repo = sửa luôn trên máy (5 mục này không cần rsync nữa).
Thêm `state/noctalia/settings.toml`: Noctalia ghi settings **xuyên symlink** thẳng vào repo — đổi theme/setting là thấy diff ngay trong git.

### Thử thay đổi cách ly bằng worktree

```bash
cd ~/Projects/dotfiles
git worktree add .worktrees/<tên> -b <tên>
# sửa config trong .worktrees/<tên>/config/...
./wt-prep.sh .worktrees/<tên>     # copy file máy-specific bị gitignore (gpu, current_wallpaper)
cd .worktrees/<tên> && ./install.sh hypr noctalia quickshell matugen rofi   # trỏ live vào worktree để xem trước

# ưng → merge vào main rồi trỏ live về main (đã gồm thay đổi):
cd ~/Projects/dotfiles && git merge <tên> && ./install.sh hypr noctalia quickshell matugen rofi
# không ưng → trỏ live về main như cũ:
cd ~/Projects/dotfiles && ./install.sh hypr noctalia quickshell matugen rofi
```

### Reload + rollback
- Hyprland: `hyprctl reload` + `hyprctl configerrors`
- Noctalia: `noctalia msg config-reload` (đổi palette: `noctalia msg color-palette-reload`)
- Rollback: `git reset --hard <commit>` + reload; backup mỗi lần cài symlink: `~/.config/backups/dotfiles-<timestamp>/`
- Quy tắc cho agent (opencode/codex): xem `AGENTS.md` trong repo.
