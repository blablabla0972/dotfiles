# Kết quả preview adaptive rice, 2026-10-25

## Trạng thái bàn giao
- Preview đang active trong `/home/admin/Projects/dotfiles/.worktrees/adaptive-unified-20261025`, nhánh `rice-adaptive-unified-20261025`.
- Tất cả nhóm desktop đã chuyển về cùng worktree; riêng Micro chỉ link settings.json, giữ dữ liệu khác.
- Không merge, không commit baseline/thay đổi sẵn có của người dùng. HEAD nền f360393.
- Diff nhánh có cả baseline live và thay đổi triển khai; đối chiếu manifest/diff sao lưu trước khi tích hợp, không git add -A một cách máy móc.
- Thay đổi tracked gốc ở main và full-visual-rice-20261024 được so byte với snapshot: không đổi.
- Wallpaper người dùng đổi trong phiên đã được giữ nguyên, không đưa về ảnh hồ cá cũ.

## Kiểm tra đã thực hiện
- Unit tests: 13, qua. Có hồi quy cho capsule/group override, pill workspace và rollback Micro mới.
- Ma trận: 14 trường hợp, 7 nhóm wallpaper × 2 mode, render template thật trong XDG tạm.
- Tương phản thấp nhất, bao gồm 6 ANSI và terminal composite: **5.36:1**, lớn hơn ngưỡng 4,5:1.
- Workspace regular: kiểm tra chữ trên fill theo API native, empty fill alpha 0,55. Đã sửa sai khác so với kế hoạch ban đầu vốn coi các khóa này như màu chữ.
- Micro mở/thoát thật trong PTY ở dark và light, có tiếng Việt, không lỗi parse màu.
- Wallpaper picker chạy thật ở dark/light, đọc đúng accent; không còn 3 literal xanh cũ.
- Native light/dark: Kitty và Micro đồng bộ, cuối bài thử trở về dark.
- Hai yêu cầu wallpaper liên tiếp qua lock, có đường dẫn tiếng Việt và khoảng trắng: qua.
- Wallpaper không tồn tại bị từ chối; hash các output không đổi.
- Rollback topology được chạy trong fixture tạm: symlink và regular file phục hồi đúng, không đè nguồn cũ.
- Nautilus, GNOME Text Editor, qt6ct và fullscreen được mở/chụp/đóng trong workspace trống; quay về workspace trước đó.
- Qt font đã kiểm tra bằng QFont thật: chuỗi 10 trường phải dùng weight 50, không phải 400 (400 ở định dạng này thành weight 900). Ảnh cuối xác nhận độ đậm bình thường.
- Hyprland configerrors sạch, Noctalia validate qua; không thêm cấu hình autostart/daemon.
- Source diff không có whitespace error. Generated GTK4 CSS có một trailing space ở template native Noctalia, chỉ hiện trong diff khi accent thay đổi; giữ nguyên quyền sở hữu generator, không sửa tay output để làm lint qua.

## Hiệu năng quan sát
Mỗi giai đoạn có 3 mẫu, mỗi mẫu khoảng 60 giây; CPU tính từ delta /proc, không dùng CPU tích lũy của ps.

| Chỉ số trung vị | Trước | Sau | Chênh lệch |
|---|---:|---:|---:|
| CPU Hyprland + Noctalia, % một core | 19.586 | 18.305 | -1.281 điểm |
| RSS Hyprland + Noctalia, MiB | 41.68 | 61.29 | +19.61 |

Các mức quan sát nằm trong ngân sách +2 điểm CPU / +50 MiB RSS. Đây là phiên live có công việc, video và kiểm tra UI, workload không được kiểm soát giống hệt nhau; chưa coi là benchmark nhân quả hoặc nghiệm thu hiệu năng có kiểm soát. Swap hệ thống vẫn hoạt động nhiều. Không đổi driver, swap hay dịch vụ hệ thống.

## Giới hạn và nghiệm thu thủ công
- Chưa khóa phiên hiện tại vì cần người dùng mở khóa; chưa logout/reboot khi người dùng đang làm việc. Kiểm tra SUPER+L, mật khẩu, suspend/resume và đăng nhập lại trước khi merge.
- Chưa nghiệm thu màn hình ngoài hoặc xác nhận chủ quan animation/độ trễ của người dùng.
- Log GUI có cảnh báo portal, Tracker và backend Enchant thiếu thư viện; không phát hiện lỗi CSS parsing do các import đã sửa. Các cảnh báo này nằm ngoài phạm vi rice, không tự cài thêm gói để che log.
- QML smoke có cảnh báo đăng ký app ID với portal; picker vẫn load, nhận palette và thoát thành công.

## Backup, ảnh và log
Toàn bộ dữ liệu máy nằm ngoài Git tại `/home/admin/.local/state/rice-upgrade/20261025-195117`.
- `manifest.json`, Git diff và bản sao live: baseline gốc.
- `preview-final.png`, `preview-launcher.png`, `preview-qt-font.png`: ảnh cuối theo wallpaper hiện tại.
- `after-two-windows.png`, `after-control-center.png`, `after-notification.png`, `after-gtk-qt.png`, `after-fullscreen.png`: ảnh kiểm tra, có thể thuộc wallpaper tại thời điểm kiểm tra.
- `unit.log`, `matrix.log`, `palette-matrix.json`, `activation.log`, `mode-test.log`, `wallpaper-live-*.log`: kết quả chi tiết.
- `performance-before.json`, `performance-after.json`, `measure.py`: phép đo có thể chạy lại.

Rollback về chính xác topology ban đầu:
```sh
python3 /home/admin/.local/state/rice-upgrade/20261025-195117/rollback.py
```
Lệnh này trả cả wallpaper selection/state về snapshot ban đầu. Không chạy nếu muốn giữ các tùy chọn giao diện mới chưa được sao lưu bổ sung. Worktree preview được giữ để tiếp tục review; không archive hoặc xóa các worktree cũ.

## Cập nhật bar và khoảng trống cửa sổ
Thông số hiện tại đã được tinh chỉnh theo phản hồi trực tiếp; xem `2026-10-25-bar-refinement.md`. Đệm capsule11, khoảng cách ngoài10, bar38; gaps dọc6 và ngang12.
