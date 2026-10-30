# Kế hoạch audit lỗi và hiệu năng rice

Trạng thái: đề xuất; chưa audit source, chưa sửa hoặc reload desktop.
Repo: https://github.com/blablabla0972/dotfiles
Checkout: /home/admin/Projects/dotfiles

## Mục tiêu và cách tiếp cận

Tìm lỗi có bằng chứng và giảm chi phí runtime, giữ giao diện và chức năng hiện tại làm mặc định.
Chọn audit theo luồng đang chạy, đo rồi sửa từng điểm nghẽn; không mặc định tắt blur/animation để đổi lấy tốc độ.
Hai hướng khác: chỉ đọc cấu hình (nhanh nhưng không chứng minh hiệu năng), hoặc rà mọi snapshot và giảm hiệu ứng hàng loạt (rộng nhưng dễ tối ưu sai mục tiêu).
Đây là kế hoạch điều tra; kế hoạch triển khai theo file chỉ viết sau khi có finding được xác minh.

## Thông tin đã kiểm tra

- Remote local khớp URL người dùng gửi; checkout hiện ở main, có nhiều thay đổi chưa commit và file chưa theo dõi. Không stage, reset hoặc ghi đè chúng.
- Symlink thực tế tại thời điểm lập kế hoạch: Hyprland → main/config/hypr; Quickshell và Noctalia → .worktrees/perf-panel-20261029/config/{quickshell,noctalia}.
- README mô tả kiến trúc Lua/UWSM, Noctalia, Quickshell, swww và pipeline theme; chưa xác minh version/process thực tế.
- docs/DEVELOPMENT.md ghi kết quả cũ: 121 tests, IPC Hyprland không truy cập được ở lần kiểm tra trước, benchmark thumbnail synthetic có cache. Đây không phải kết quả của phiên hiện tại hoặc bằng chứng FPS carousel.
- Có .codegraph/: dùng index trước khi truy tìm source; kiểm tra kết quả với source của đúng checkout đang chạy, không mặc định index phản ánh worktree.

## Phân công

| Bên | Trách nhiệm |
| --- | --- |
| Codex | Xác định cấu hình thực chạy, đo runtime, tái hiện lỗi, xác minh finding AGY, tổng hợp ưu tiên; về sau thực hiện và kiểm chứng patch |
| AGY | Review tĩnh theo batch file xác định, trả path/dòng/trigger/bằng chứng/giới hạn; review độc lập diff, không tự đổi desktop hoặc chạy benchmark song song |
| Ponytail | Lượt riêng về code thừa, wrapper, polling/abstraction không cần thiết; đề xuất đơn giản hóa không tự được coi là cải thiện hiệu năng |
| Superpowers | Điều tra nguyên nhân trước khi sửa, task nhỏ với kiểm chứng phù hợp, cô lập thay đổi, review và nghiệm thu có bằng chứng |

## Các giai đoạn

- [x] 1. Chụp trạng thái: revision, dirty files và live symlink của từng thành phần; version, GPU, monitor/refresh/scale, session/IPC, profile nguồn và process/cgroup liên quan. Phân biệt source repo, source worktree đang preview, binary đang chạy và file sinh.
- [x] 2. Lấy baseline: idle sau warm-up và các thao tác tái hiện được (mở carousel, chuyển cửa sổ/workspace, đổi wallpaper khi bước thử live được thống nhất). Ghi CPU, RSS/PSS nếu có, process con, wakeups/I/O và độ trễ tương ứng; chỉ báo frame pacing khi có phép đo phù hợp. Tách cold/warm cache; lặp ít nhất 5 lượt với thao tác ngắn, báo median và khoảng dao động; ghi rõ thời gian lấy mẫu idle.
- [x] 3. AGY review các batch source đang active: (a) Lua autostart và systemd/UWSM, (b) QML/JS/helpers carousel được entry point tham chiếu, (c) theme transaction/hooks/cache. Codex đồng thời làm đo runtime độc lập; không hai bên lặp cùng cuộc rà soát. Mở rộng phạm vi chỉ khi có import/call path hoặc finding cụ thể.
- [x] 4. Codex xác minh: tái hiện hoặc kiểm tra bằng chứng từng finding; tách confirmed, suspected và không tái hiện. Ponytail đề xuất phần có thể bỏ/đơn giản hóa. Xếp ưu tiên: lỗi mất trạng thái/race/process trùng, CPU/wakeups kéo dài, độ trễ thao tác, rồi mới cleanup.
- [x] 5. Sau khi thống nhất xử lý: task theo finding, worktree mới từ baseline đã ghi nhận và mang đúng phần thay đổi cần thiết từ bản đang chạy bằng diff được review; không mặc định HEAD là bản live. Một người sửa mỗi worktree; AGY review diff. Viết kiểm thử hồi quy cho logic lỗi phù hợp; không thêm test hình thức cho thay đổi nhỏ.
- [x] 6. Kiểm chứng: focused tests và suite theo DEVELOPMENT.md khi đổi behavior; palette matrix khi đổi màu/template; syntax/native validation liên quan. Chạy trong môi trường tạm khi có thể; chỉ preview các component đã đổi với --no-state sau dry-run và chuẩn bị rollback. Đo A/B cùng điều kiện, kiểm tra giao diện, nhập liệu, lockscreen và lỗi IPC/log liên quan.
- [x] 7. Bàn giao: bảng finding, patch/diff, số đo trước/sau, test failures/skips, giới hạn và rollback; ghi checkpoint để tiếp tục qua phiên mới. Merge/push không thuộc giai đoạn lập kế hoạch.

## Quy tắc đo và an toàn

- Không đổi CPU governor, GPU power state, driver, monitor hay dịch vụ để tạo benchmark đẹp; ghi điều kiện hiện tại và kiểm soát nhiễu. Không cài daemon giám sát mới.
- Tính đủ process con/cgroup, không cộng trùng; CPU% cần chỉ rõ cách chuẩn hóa, mẫu số và khoảng lấy mẫu. Không quy RSS cộng dồn thành tổng RAM độc quyền.
- Phân biệt chi phí burst khi sinh theme với idle; thời gian script thumbnail không đại diện thời gian khung hình.
- Nếu IPC/quyền/công cụ không đủ, đánh dấu phép đo bị chặn; không suy FPS hoặc nghiệm thu visual từ offline tests.
- Chỉ đọc không cần worktree; mọi thay đổi behavior/config cần worktree cách ly. Không install, reload, đổi wallpaper hay động tới state trong audit tĩnh.
- Giữ dark default, lock clock layout, wallpaper/GPU links và thay đổi của người dùng. Không sửa tay output sinh; giữ owner transaction, acknowledgment và rollback.
- Kiểm tra AGENTS.md gần file trước khi sửa; không quét home, backup hoặc source ngoài repo để tìm manh mối. Nếu binary Noctalia nằm ngoài repo, ghi giới hạn và chỉ mở rộng khi được cho phép.
- Chỉ tra tài liệu chính thức/Context7 khi có câu hỏi API/version cụ thể; không áp cú pháp config nhớ từ phiên bản khác.

## Tiêu chí nhận finding và patch

Mỗi finding có ID, checkout/path:dòng, trigger, expected/actual, bằng chứng, mức ảnh hưởng, độ chắc chắn, hướng sửa và cách kiểm chứng.
Patch hiệu năng cần cải thiện đo được vượt nhiễu ở chỉ số mục tiêu, không gây suy giảm đáng kể ở chỉ số/giao diện liên quan; không hứa mức phần trăm trước khi đo.
Patch sửa lỗi cần kiểm chứng trigger đã hết lỗi; giảm số dòng tự nó không chứng minh tăng tốc.
Các lỗi có sẵn phải được phân biệt với lỗi mới; báo chính xác pass/fail/skips và hạng mục chưa thể kiểm tra.

## Phản biện AGY đã thu thập

Job staffer-mvuievw1-313f999d phản biện kế hoạch, không đọc repo hoặc xác nhận bug.
Tiếp nhận: tính process/cgroup đầy đủ, tách burst/idle, tránh hai bên đo trùng, review độc lập.
Không tiếp nhận đề nghị bắt buộc đổi governor hay tạo worktree trước mọi thao tác chỉ đọc: chưa có căn cứ và không cần thiết cho audit này.
Đã hiệu chỉnh giả định AGY rằng tất cả symlink trỏ main bằng kết quả readlink thực tế nêu trên.

## Checkpoint thực thi

Đã audit theo batch và sửa trong .worktrees/rice-audit-agy-20261030, base perf-panel 67a3c04: chọn đúng wallpaper, hỗ trợ thumbnail symlink/library liên kết, fallback lookup không khởi chạy và bỏ preview churn khi rebuild. AGY review cuối approve; 140 tests pass không skip, palette matrix/syntax/diff checks pass. Đã preview riêng quickshell bằng --no-state, bảo toàn state và target khác. Benchmark cache thường không thay đổi đáng kể; chưa có bằng chứng tăng FPS. Màn hình đang khóa nên visual/FPS acceptance còn pending; chưa merge/push. Báo cáo đầy đủ: .worktrees/rice-audit-agy-20261030/docs/rice/AUDIT_20261030.md.

Nghiệm thu sau mở khóa đã hoàn tất: screenshot live đúng carousel/wallpaper, navigation tiến/lùi và closeShell hai lượt pass, 140 tests pass lại, không QML/config errors. A/B hiển thị thật 5 lượt mỗi bản trên cùng ảnh cho CPU trung vị khoảng 0.67% một core ở cả hai bản; không chứng minh tăng FPS. Báo cáo AUDIT_20261030.md trong worktree chứa số đo, giới hạn và rollback; không còn bước bắt buộc đang chờ, chưa merge/push/commit.
