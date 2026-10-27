# Adaptive Material glass, 2026-10-25

## Quyết định và phạm vi
Giữ 5 workspace, bố cục bar/dock/widget, phím tắt, Matugen thích ứng và đồng hồ Hyprlock. Dark mặc định, hỗ trợ light. Không thay driver, hệ thống, C++ Noctalia hoặc thêm daemon.

## Môi trường
Hyprland 0.56.2 Lua; Noctalia 5.3.0 native tùy biến; Matugen 4.2.0; Quickshell 0.3.2; Kitty 0.49.2. Binary Noctalia: `/home/admin/noctalia-dashboard-redesign/build-v5.3-material-glass-native/noctalia`.

## Token giao diện
- UI Adwaita Sans 11, ui_scale 1.20; bar scale 1.00. Mono JetBrainsMono Nerd Font 12, padding 16.
- Gaps 6/12, border 2, window radius 16; blur size 6 / passes 2; shadow range 24, power 3, alpha 0x38.
- Bar thickness 38, margin 12, radius 19, capsule surface_variant / 0.92; nền tổng thể trong suốt.
- Shell radius scale 1, glass, shadow 0.30; launcher/control center giữ 760/950.
- Notification 380, tối đa 3, offsets 12/64; OSD Y64; opacity 0.92.
- Dock radius24, margin12, opacity0.92, magnification1.12; media background0.92. Kitty0.94.
- Window popin96%, speed3/easeOutQuint. Workspace slide3/quick, special2.
- Chữ thường on_surface/on_surface_variant; accent primary/on_primary; outline chỉ dùng cho viền. Workspace regular dùng màu nền pill: occupied=secondary, empty=surface_variant, focused=primary, nhãn do Noctalia chọn theo on-role.
- ANSI custom seeds đỏ, xanh lá, vàng, xanh dương, tím, cyan được Matugen blend; không ghim accent.

## File sinh tự động
Không sửa tay `hypr/colors.conf`, `hypr/noctalia.lua`, `noctalia/palettes/matugen.json`, các template ứng dụng Noctalia hoặc `micro/colorschemes/adaptive.micro`. Sửa template Matugen hoặc cấu hình nguồn.

## Backup và rollback
Snapshot ngoài Git: `/home/admin/.local/state/rice-upgrade/20261025-195117`.
Rollback: `python3 /home/admin/.local/state/rice-upgrade/20261025-195117/rollback.py`.
Manifest giữ nguyên topology hỗn hợp ban đầu và nội dung regular files. Rollback không ghi đè các thư mục nguồn cũ. Các thay đổi của người dùng ở main/worktree cũ được giữ nguyên, không reset/stash/commit.

## Trạng thái tích hợp
Nhánh preview: `rice-adaptive-unified-20261025` (không thể dùng tiền tố `rice/` vì nhánh `rice` đã tồn tại). Worktree: `/home/admin/Projects/dotfiles/.worktrees/adaptive-unified-20261025`.
Native create_worktree không áp dụng được vì chat bắt đầu trong `.config`, không phải Git repo; đã dùng git worktree tại repo được chỉ định.
Chưa merge; diff gồm baseline cấu hình live và các chỉnh sửa triển khai. Commit nền main: f360393. Không commit thay đổi sẵn có của người dùng.

## Kiểm tra
Kết quả chi tiết được bổ sung sau preview trong `2026-10-25-adaptive-results.md`. Log, ảnh và số đo nằm trong snapshot ngoài Git.
