# Dotfiles — CachyOS + Hyprland

Bản lưu cấu hình hệ sinh thái Hyprland trên máy `admin` (CachyOS, Hyprland 0.56.2).

## Cấu trúc

```
dotfiles/
├── config/          # symlink → ~/.config/<tên>
│   ├── hypr/        # Hyprland (backend Lua), hyprlock, scripts
│   ├── noctalia/    # Bar/shell Noctalia (thay waybar + dunst + swww UI)
│   ├── matugen/     # Sinh màu từ wallpaper
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
# Replace OWNER with the GitHub owner of this repository.
git clone https://github.com/OWNER/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run   # xem trước
./install.sh             # cài cấu hình desktop live mặc định (backup file cũ an toàn)
./install.sh --all       # cài toàn bộ (bao gồm cả systemd và snapshot máy)
./install.sh hypr noctalia   # chỉ cài vài mục
```

`--all` and an explicit `noctalia` selector can install `state/noctalia/settings.toml`; add `--no-state` to preserve the destination machine's runtime session settings. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for test commands, file ownership, and task completion checks.

## Đồng bộ sau khi sửa cấu hình

Chỉ đồng bộ các file đã chọn; tránh `rsync --delete` và `git add -A` trên snapshot có file runtime hoặc cấu hình riêng máy.

```bash
cd ~/Projects/dotfiles
git status --short
git diff -- config/hypr
# Stage only the paths you reviewed, then inspect the staged diff.
git add -- config/hypr/FILE
git diff --cached --check
git diff --cached
```

Replace `FILE` with a specific reviewed path. Keep generated and machine-specific files out unless the task explicitly changes their source or ownership.

## Lưu ý khi dùng trên máy khác

Các symlink sau là machine-specific và đã được gitignore, không dùng chung giữa các máy khác nhau:

- `config/hypr/current_wallpaper` → một ảnh trong `~/Ảnh/Wallpaper`
- `config/hypr/gpu/{intel,nvidia}` → `/dev/dri/by-path/...` (theo PCI của máy)

Các dịch vụ systemd user dùng specifier `%h`, Qt6ct dùng đường dẫn `~/.config/qt6ct/colors/noctalia.conf` và các symlink nội bộ là tương đối để giảm phụ thuộc vào đường dẫn home. Khi chuyển sang máy khác, vẫn cần chuẩn bị wallpaper, liên kết GPU theo phần cứng, font/icon và các chương trình tương ứng trong bảng hệ sinh thái bên dưới; kiểm tra cấu hình màn hình trước khi áp dụng.

Sau khi chuẩn bị ảnh nền, chạy `python3 ~/.config/hypr/scripts/generate-theme.py --apply-wallpaper /path/to/wallpaper.jpg` để tái sinh theme. `config/hypr/colors.conf` là file sinh và có thể còn ghi đường dẫn wallpaper của máy cũ; không sửa tay file này.

Mục `state/noctalia/settings.toml` lưu trạng thái session và bố cục widget lockscreen của máy này. Mặc định `./install.sh` sẽ không cài đè file này để tránh xung đột màn hình; muốn áp dụng trạng thái này lên máy mới hãy chạy `./install.sh noctalia` (hoặc `./install.sh --all`).

## Hệ sinh thái đang dùng

| Thành phần | Vai trò |
|---|---|
| Hyprland 0.56.2 | Compositor, config backend **Lua** (`hyprland.lua` load 11 module trong `config/`) |
| Noctalia | Bar + notification + control center (thay waybar/dunst/swaync) |
| swww | Wallpaper daemon (chạy qua systemd user unit) |
| matugen | Sinh màu từ wallpaper → `hypr/colors.conf` |
| hyprlock | Màn hình khóa |
| fcitx5 + Bamboo | Nhập tiếng Việt |

## Workflow rice với worktree (từ 2026-10-16)

Các thành phần desktop đang dùng là symlink vào checkout live (nhánh `main`):
`~/.config/{hypr,noctalia,quickshell,matugen,rice,micro,kitty,alacritty,gtk-3.0,gtk-4.0,qt5ct,qt6ct,btop}` → `config/*`; `~/.config/kdeglobals` → `root/kdeglobals`.
`~/.local/bin/toggle-desktop` → `bin/toggle-desktop`.
Sửa trong `config/` của repo = sửa luôn trên máy.
Trên máy khác, cài riêng trạng thái Noctalia chỉ khi muốn thay trạng thái của máy đó: `./install.sh noctalia`. Dùng `--no-state` để giữ state hiện tại.

### Thử thay đổi cách ly bằng worktree

```bash
cd ~/Projects/dotfiles
worktree=.worktrees/rice-example
branch=feat/rice-example
components=(hypr quickshell matugen rice) # replace with the components actually changed
git worktree add "$worktree" -b "$branch"
./wt-prep.sh "$worktree" # only for a new worktree; copies host-specific wallpaper/GPU inputs
cd "$worktree"
./install.sh --dry-run --no-state "${components[@]}"
./install.sh --no-state "${components[@]}" # preview the selected components

# After review, fast-forward main and install the same selected components:
cd ~/Projects/dotfiles
git merge --ff-only "$branch"
./install.sh --dry-run --no-state "${components[@]}"
./install.sh --no-state "${components[@]}"
```

To discard a preview before merging, restore the main symlinks for the same components and regenerate changed theme outputs with the theme owner. Inspect installer backups before restoring replaced paths. Do not reuse a feature-specific preview/rollback helper after its recorded base revision has advanced.

### Reload + rollback
- Hyprland: `hyprctl reload` + `hyprctl configerrors`
- Noctalia: `noctalia msg config-reload` (đổi palette: `noctalia msg color-palette-reload`)
- Rollback: `git revert <commit-rice>` rồi cài lại các mục đã đổi và reload; backup mỗi lần cài symlink: `~/.config/backups/dotfiles-<timestamp>/`.
- Quy tắc cho agent (opencode/codex): xem `AGENTS.md` trong repo.
- Build/test commands, generated-file ownership, and agent handoff criteria: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Adaptive rice

Bar nổi chia nhóm, font Adwaita Sans, cửa sổ bo góc nhẹ và launcher Noctalia với hiệu ứng kính. Màu lấy từ wallpaper qua Matugen. Mặc định **dark**, giữ bố cục màn hình khóa ban đầu với đồng hồ giờ/phút không có khung.

```bash
# Đổi wallpaper và đồng bộ toàn bộ giao diện
python3 ~/.config/hypr/scripts/generate-theme.py --apply-wallpaper /path/to/wallpaper.jpg

# Hook tự cập nhật Matugen, GTK/Qt và các template ứng dụng
noctalia msg theme-mode-set dark
# Chế độ sáng cũng được hỗ trợ khi cần
noctalia msg theme-mode-set light
```

Hook `wallpaper_changed` giữ các cách chọn wallpaper hiện có hoạt động; `theme_mode_changed` đồng bộ màu khi chuyển sáng/tối. Bề mặt và chữ dùng các vai trò màu tương ứng, không ghim màu accent. Các cấu hình ứng dụng trong đợt rice này được cài bằng symlink để màu sinh ra được lưu đúng vào dotfiles.

```bash
./install.sh hypr noctalia matugen kitty alacritty gtk-3.0 gtk-4.0 qt5ct qt6ct btop kdeglobals
hyprctl reload
noctalia msg config-reload

# Ma trận dựng template trong thư mục tạm; không thay đổi desktop
python3 -m unittest discover -s tests -q
python3 tests/check_palette_matrix.py --no-desktop
```

Kế hoạch, quyết định thiết kế và kết quả nghiệm thu nằm trong `docs/rice/`. Ảnh preview và backup máy được giữ cục bộ, không đưa lên GitHub. Mỗi lần áp wallpaper đều có snapshot ở `~/.local/state/desktop-wallpaper/backups/`.

Quiet Current: thư viện token semantic nằm ở `config/rice/theme/`, output giao dịch ở `$XDG_STATE_HOME/desktop-wallpaper/adaptive-theme.json`; carousel dùng acknowledgment và preview màu chỉ đọc. Quy trình preview/rollback/chốt merge: `docs/rice/APPLY_QUIET_CURRENT.md`; dùng `install.sh --no-state` khi chọn Noctalia mà cần giữ session/lock settings.
