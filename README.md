# Dotfiles — CachyOS + Hyprland

Bản lưu cấu hình hệ sinh thái Hyprland trên máy `admin` (CachyOS, backend Lua).

## Cấu trúc

```
dotfiles/
├── config/          # symlink → ~/.config/<tên>
│   ├── hypr/        # Hyprland (backend Lua), hyprlock, scripts
│   ├── noctalia/    # Cấu hình shell legacy / fallback
│   ├── matugen/     # Sinh màu từ wallpaper
│   ├── quickshell/  # Rice shell (bar, island, dashboard) + wallpaper switcher
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
./install.sh hypr quickshell   # chỉ cài vài mục
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

## Hệ sinh thái và đường chạy mặc định

`config/hypr/config/autostart.lua` ưu tiên chạy `quickshell -d -p ~/.config/quickshell/rice-shell` và khởi động `hypridle` với `hypridle.conf`. Noctalia chỉ là fallback khi không chạy được Quickshell; cấu hình và state Noctalia vẫn được giữ để khôi phục hệ cũ.

### Noctalia legacy / khôi phục

Phiên bản Noctalia legacy dùng bản native C++23 v5.4.1 đã patch, có `theme.matugen_palette`;
gói upstream chưa patch không đủ cho pipeline này. Mã nguồn được quản lý ở
[noctalia-dashboard-source](https://github.com/blablabla0972/noctalia-dashboard-source),
còn patch, hướng dẫn build và launcher nằm trong
[noctalia-dashboard-redesign](https://github.com/blablabla0972/noctalia-dashboard-redesign)
(`README.md`, `DELIVERY.md`). Installer dotfiles chỉ tạo symlink cấu hình, không
build hoặc cài binary này; chuẩn bị binary và assets cùng revision trước khi cài.
Launcher `~/.local/bin/noctalia` phải export `NOCTALIA_ASSETS_DIR` tới thư mục assets
của bản build rồi `exec` binary với `"$@"`; thay đường dẫn home của máy cũ khi dựng lại.
Launcher Noctalia legacy `run-noctalia.sh` dùng
`worktrees/noctalia-upgrade-current/build-v5.4.1-matugen/noctalia` và
`worktrees/noctalia-upgrade-current/assets` trong `~/noctalia-dashboard-redesign`.
Buildtype là `release`, nên không có debug indicator trên top bar.
Kiểm tra bằng `noctalia config validate` trước khi bật autostart.
Revision source `0cfb9f8dde4a7b36ebde4627f2d7274450d5c755` (VERSION 5.4.1) đã được lưu trên nhánh
[`codex/noctalia-v5.4.1-current`](https://github.com/blablabla0972/noctalia-dashboard-source/tree/codex/noctalia-v5.4.1-current).
Dùng [hướng dẫn khôi phục](docs/RESTORE.md) để lấy đúng source, build và chuẩn bị launcher;
các tài liệu v5.2.1/v5.3.0 trong repo redesign là lịch sử, không phải phiên bản hiện chạy.

### Các thành phần trong cấu hình hiện tại

| Thành phần | Vai trò |
|---|---|
| Hyprland | Compositor, config backend **Lua** (`hyprland.lua` load module trong `config/`) |
| Quickshell rice-shell | Bar + Dynamic Island + notification + control center |
| Noctalia | Shell legacy / fallback khi Quickshell không khởi động được |
| swww | Wallpaper daemon (chạy qua systemd user unit) |
| matugen | Sinh màu từ wallpaper → `hypr/colors.conf` |
| hyprlock / hypridle | Khóa màn hình và điều khiển idle, được khởi chạy trong `autostart.lua` |
| fcitx5 + Bamboo | Nhập tiếng Việt |

Với cấu hình Quickshell, `hypridle.conf` giảm sáng sau 3 phút, khóa sau 5 phút, tắt màn hình sau 6 phút và suspend sau 30 phút; khi quay lại sẽ khôi phục độ sáng. Nếu chủ động chuyển về Noctalia legacy, kiểm tra và chỉ giữ một trình quản lý idle để tránh hai bộ timeout cùng hoạt động. Hermes là service tùy chọn: `--all` không tự bật gateway; chỉ bật thủ công trên máy đã cài Hermes. Unit sẽ bỏ qua khởi động nếu thiếu executable.

Service swww dùng `ExecSearchPath` của systemd ≥250 để tìm daemon trong `~/.local/bin` hoặc `/usr/bin`. Carousel tạo thumbnail ngay khi mở và nạp dần từ cache; chuyển wallpaper lấy FPS từ màn hình đang bật (mặc định 60 khi không đọc được IPC). GTK4 dùng CSS semantic cho cả dark/light, và Brave không còn ép dark mode. Artifact `graphify-out/` được giữ cục bộ, không theo dõi trong Git.

## Workflow rice với worktree (từ 2026-10-16)

Các thành phần desktop dùng symlink vào checkout live (phần lớn trên nhánh `main`):
`~/.config/{hypr,noctalia,quickshell,matugen,rice,micro,kitty,alacritty,gtk-3.0,gtk-4.0,qt5ct,qt6ct,btop}` → `config/*`; `~/.config/kdeglobals` → `root/kdeglobals`.
`~/.local/bin/toggle-desktop` → `bin/toggle-desktop`.
Tại checkpoint 2026-11-11, toàn bộ liên kết cấu hình live được quản lý ở trên đều trỏ vào checkout `main`; các preview cũ không còn được cài. Luôn resolve liên kết thực tế trước khi sửa vì một lần preview sau có thể đổi checkout đích.
Chỉ sửa trong checkout được các symlink live trỏ tới mới tác động trực tiếp lên máy; worktree cách ly không tự cập nhật cấu hình đang chạy.
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
- Quickshell rice-shell: IPC `rice.reloadShell` hoặc reload theo phiên Quickshell đang chạy
- Noctalia legacy: `noctalia msg config-reload` (đổi palette: `noctalia msg color-palette-reload`)
- Rollback: `git revert <commit-rice>` rồi cài lại các mục đã đổi và reload; backup mỗi lần cài symlink: `~/.config/backups/dotfiles-<timestamp>/`.
- Quy tắc cho agent (opencode/codex): xem `AGENTS.md` trong repo.
- Build/test commands, generated-file ownership, and agent handoff criteria: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Adaptive rice

Bar Quickshell nổi chia nhóm cùng Dynamic Island, dashboard và launcher; màu lấy từ wallpaper qua Matugen. Pipeline hỗ trợ cả **dark** và **light**.

```bash
# Đổi wallpaper và đồng bộ toàn bộ giao diện
python3 ~/.config/hypr/scripts/generate-theme.py --apply-wallpaper /path/to/wallpaper.jpg

# Đồng bộ Matugen, GTK/Qt và các template ứng dụng theo chế độ màu
python3 ~/.config/hypr/scripts/generate-theme.py --theme-mode-changed --backend quickshell --mode dark
# Chuyển sang chế độ sáng
python3 ~/.config/hypr/scripts/generate-theme.py --theme-mode-changed --backend quickshell --mode light
```

Hook `wallpaper_changed` giữ các cách chọn wallpaper hiện có hoạt động; `theme_mode_changed` đồng bộ màu khi chuyển sáng/tối. Bề mặt và chữ dùng các vai trò màu tương ứng, không ghim màu accent. Các cấu hình ứng dụng trong đợt rice này được cài bằng symlink để màu sinh ra được lưu đúng vào dotfiles.

```bash
./install.sh hypr quickshell matugen kitty alacritty gtk-3.0 gtk-4.0 qt5ct qt6ct btop kdeglobals
hyprctl reload

# Ma trận dựng template trong thư mục tạm; không thay đổi desktop
python3 -m unittest discover -s tests -q
python3 tests/check_palette_matrix.py --no-desktop
```

Kế hoạch, quyết định thiết kế và kết quả nghiệm thu nằm trong `docs/rice/`. Ảnh preview và backup máy được giữ cục bộ, không đưa lên GitHub. Mỗi lần áp wallpaper đều có snapshot ở `~/.local/state/desktop-wallpaper/backups/`.

Quiet Current: thư viện token semantic nằm ở `config/rice/theme/`, output giao dịch ở `$XDG_STATE_HOME/desktop-wallpaper/adaptive-theme.json`; carousel dùng acknowledgment và preview màu chỉ đọc. Quy trình preview/rollback/chốt merge: `docs/rice/APPLY_QUIET_CURRENT.md`; dùng `install.sh --no-state` khi chọn Noctalia mà cần giữ session/lock settings.
