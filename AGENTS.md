# AGENTS — dotfiles/rice (máy admin, CachyOS + Hyprland Lua backend)

Live config của máy này là **symlink** vào repo này:
`~/.config/{hypr,noctalia,quickshell,matugen,rofi}` → `config/*` (nhánh `main`).
Thêm `~/.local/state/noctalia/settings.toml` → `state/noctalia/settings.toml` (Noctalia ghi settings xuyên symlink vào repo).

## Nguyên tắc
- Đổi rice: làm trong **worktree** `.worktrees/<tên>` (nhánh riêng). Không sửa thẳng `main` trừ khi user yêu cầu.
- Trước khi preview từ worktree: `./wt-prep.sh .worktrees/<tên>` (copy file máy-specific bị gitignore: `gpu/`, `current_wallpaper`, `wallpaper_thumb.jpg`).
- Preview trên máy: `cd .worktrees/<tên> && ./install.sh <mục>` rồi reload. Quay về: `cd ~/Projects/dotfiles && ./install.sh <mục>`.
- Apply: `git merge <tên>` vào `main` rồi `./install.sh` từ repo (live tự theo `main`).
- Reload: `hyprctl reload` + `hyprctl configerrors`; Noctalia: `noctalia msg config-reload`; palette: `noctalia msg color-palette-reload`.
- KHÔNG sửa tay file generated: `config/hypr/colors.conf`, `config/hypr/noctalia.lua`, `config/rofi/colors.rasi`, `config/noctalia/palettes/matugen.json` (do `config/hypr/scripts/generate-theme.py` sinh).
- `state/noctalia/settings.toml` do Noctalia tự ghi (settings UI / `noctalia msg`) — diff trong git là bình thường, commit khi muốn chốt. Nếu symlink mất: `./install.sh noctalia`. Bản patch C++ dashboard: `~/noctalia-dashboard-redesign` (git riêng).
- Backup mỗi lần cài: `~/.config/backups/dotfiles-*`. Snapshot trước khi chuyển symlink (2026-10-16): `~/.local/state/rice-transition/`.
