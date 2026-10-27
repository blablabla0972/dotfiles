# AGENTS — dotfiles/rice (máy admin, CachyOS + Hyprland Lua backend)

Live config của máy này là **symlink** vào repo này:
`~/.config/{hypr,noctalia,quickshell,matugen,kitty,alacritty,gtk-3.0,gtk-4.0,qt5ct,qt6ct,btop}` → `config/*` (nhánh `main`).
`~/.config/kdeglobals` → `root/kdeglobals`.
`~/.local/state/noctalia/settings.toml` → `state/noctalia/settings.toml` (Noctalia ghi settings xuyên symlink vào repo).
`~/.local/bin/toggle-desktop` → `bin/toggle-desktop`.

Mọi mục còn lại trong `config/` và `root/` (fish, systemd, fcitx5...) là **snapshot**: sửa repo KHÔNG đổi máy — muốn áp lên máy thì `./install.sh <mục>` (có backup). Đồng bộ máy → repo: copy `~/.config/<mục>` vào `config/<mục>` (như commit `sync: live state`), bỏ qua file runtime đã gitignore (`*.log`, `*.bak*`, `cached_layouts`, `fish_variables`, `thumbnail.png`, `micro/syntax/`, `gpu/`, `current_wallpaper`). Tổng quan + cài máy mới: `README.md`.

## Nguyên tắc
- Launcher mặc định (`SUPER+SPACE`) là Noctalia: chỉnh `[shell.panel].transparency_mode` trong config Noctalia để đổi glass. xem bind thực tế trước khi sửa giao diện launcher.
- Giữ chế độ tối theo Matugen và bố cục lock giờ/phút ban đầu, không có khung quanh đồng hồ (lựa chọn của user sau preview 2026-10-17).
- Đổi rice: làm trong **worktree** `.worktrees/<tên>` (nhánh riêng). Không sửa thẳng `main` trừ khi user yêu cầu.
- Trước khi preview từ worktree: `./wt-prep.sh .worktrees/<tên>` (copy file máy-specific bị gitignore: `gpu/`, `current_wallpaper`).
- Preview trên máy: `cd .worktrees/<tên> && ./install.sh <mục>` rồi reload. Quay về: `cd ~/Projects/dotfiles && ./install.sh <mục>`.
- Apply: `git merge <tên>` vào `main` rồi `./install.sh` từ repo (live tự theo `main`).
- Reload: `hyprctl reload` + `hyprctl configerrors`; Noctalia: `noctalia msg config-reload`; palette: `noctalia msg color-palette-reload`.
- KHÔNG sửa tay file generated: `config/hypr/colors.conf`, `config/hypr/noctalia.lua`, `config/noctalia/palettes/matugen.json` (do `config/hypr/scripts/generate-theme.py` sinh).
- `state/noctalia/settings.toml` do Noctalia tự ghi (settings UI / `noctalia msg`) — diff trong git là bình thường, commit khi muốn chốt. Nếu symlink mất: `./install.sh noctalia`. Bản patch C++ dashboard: `~/noctalia-dashboard-redesign` (git riêng).
- Backup mỗi lần cài: `~/.config/backups/dotfiles-*`. Snapshot trước khi chuyển symlink (2026-10-16): `~/.local/state/rice-transition/`.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
