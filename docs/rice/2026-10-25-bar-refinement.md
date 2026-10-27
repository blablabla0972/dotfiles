# Tinh chỉnh bar và chiều cao cửa sổ, 25/10/2026

## Phản hồi đã làm rõ
- Icon sát đầu bo tròn là vấn đề padding bên trong capsule.
- Bản thử padding14/gap16 quá thoáng; đã thu về padding11/gap10.
- Yêu cầu tăng chiều cao áp dụng cho cửa sổ ứng dụng. Bản thử tăng chiều cao capsule đã được hoàn tác.

## Nghiên cứu và lựa chọn
- [Noctalia bar API](https://github.com/noctalia-dev/noctalia-docs/blob/main/src/content/docs/noctalia/bar/index.mdx): padding capsule/group và khoảng cách giữa widget là các thuộc tính riêng. Kiểm tra mã native đang chạy xác nhận chiều ngang capsule = nội dung + padding hai đầu.
- [Caelestia](https://github.com/caelestia-dots/shell): học cách phân cấp bằng spacing, tỷ lệ chữ và màu theo vai trò. Áp vào cấu hình Noctalia hiện có.
- [end-4](https://github.com/end-4/dots-hyprland): giữ một nguồn màu theo wallpaper, để hình học và chất liệu tạo bản sắc.
- [Noctalia sidebar frame trên unixporn](https://www.reddit.com/r/unixporn/comments/1wprjkz/hyprland_cachyos_hyprland_noctalia_shell_with_a/): tham khảo độ sâu desktop và kiểm tra cả khi có cửa sổ. Với yêu cầu tăng diện tích ứng dụng hiện tại, ưu tiên bar nổi và thu khoảng trống dọc.

## Đã áp dụng
- Launcher dùng primary/on_primary, nằm trong capsule riêng.
- Giờ đậm hơn (600, font scale1.08), ngày nhỏ hơn (0.94), cùng một capsule có padding11; màu chữ lấy từ Matugen.
- Capsule có viền outline mảnh; thông báo và nguồn được gom nhóm. Media giữ artwork, giới hạn nhãn160, ẩn khi không có media.
- Padding11 cho capsule và group; khoảng cách ngoài10, khoảng cách thành viên group12/14. Hình dạng bo tròn giữ nguyên.
- Bar thickness38, capsule fraction0.86, reserved zone52px.
- Hyprland gaps_out: top6, bottom6, left12, right12. Gaps giữa cửa sổ giữ6.
- Kích thước thực của Brave: 1892×990 → 1892×1012; Kitty và Codex: 938×990 → 938×1012, tăng22px so với bản thử trước đó. Runtime JSON lưu bằng chứng; vị trí y76 → y60.
- Tất cả trong worktree preview hiện tại, chưa merge; palette/generated files và binary Noctalia không bị sửa tay.

## Nghiệm thu
- Config Noctalia hợp lệ; Hyprland reload và configerrors sạch.
- Ma trận màu render thật và hồi quy capsule/foreground chạy lại sau chỉnh sửa.
- Ảnh cuối: `/home/admin/.local/state/rice-upgrade/20261025-bar-expressive-203806/bar-final-clean.png`; config hiệu lực: `final-effective.toml`; kích thước ứng dụng: `window-height-results.json`.
- Backup và bản thử nằm tại `/home/admin/.local/state/rice-upgrade/20261025-bar-expressive-203806`. Bản wide-spacing.toml là bản thử đã bị loại, không phải cấu hình cuối.

Rollback riêng đợt này, giữ nguyên wallpaper/state người dùng:
```sh
python3 /home/admin/.local/state/rice-upgrade/20261025-bar-expressive-203806/rollback.py
```
