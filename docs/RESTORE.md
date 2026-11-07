# Khôi phục desktop

## Chuẩn bị runtime

Đây là cấu hình CachyOS/Arch với Hyprland backend Lua 0.56.2, Quickshell,
Matugen, ImageMagick, Node.js, Python >=3.11, fcitx5/Bamboo, các terminal và
font/icon tương ứng. Installer không cài package hệ thống. Wallpaper và GPU
phải được chọn theo máy đích; xem README trước khi cài snapshot `--all`.

Noctalia phải là bản native có patch `theme.matugen_palette`. Revision đã lưu:
[`ade8aa6c17d72ee571d08d0f1b765e8894c07eb5`](https://github.com/blablabla0972/noctalia-dashboard-source/commit/ade8aa6c17d72ee571d08d0f1b765e8894c07eb5),
trên nhánh `dotfiles-runtime-20261107`, VERSION 5.3.0.
Theo [PACKAGING.md của revision này](https://github.com/blablabla0972/noctalia-dashboard-source/blob/ade8aa6c17d72ee571d08d0f1b765e8894c07eb5/PACKAGING.md),
cần C++23, Meson >=1.1, Ninja và các development dependencies của shell.
Cài cả `nlohmann-json` và `stb` trên Arch/CachyOS: source cần
`nlohmann/json.hpp`, `stb/stb_image_resize2.h`, `stb/stb_image_write.h`.
Máy hiện tại cung cấp chúng qua `~/noctalia-dashboard-redesign/build-deps`;
thư mục này không nằm trong clone source, nên đừng sao chép các đường dẫn
`-I/home/admin/...` hay file `.pc` có prefix tuyệt đối sang máy mới.

```sh
git clone --branch dotfiles-runtime-20261107 \
  https://github.com/blablabla0972/noctalia-dashboard-source.git \
  "$HOME/Projects/noctalia-runtime"
cd "$HOME/Projects/noctalia-runtime"
git checkout --detach ade8aa6c17d72ee571d08d0f1b765e8894c07eb5
meson setup build --buildtype=release --wrap-mode=nofallback -Dtests=disabled
meson compile -C build noctalia -j4
```

Nếu setup báo thiếu dependency, cài development package tương ứng trước khi
tiếp tục. Không thay bản system trong `/usr/bin`; tạo launcher user portable:

```sh
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/noctalia" <<'SH'
#!/bin/sh
runtime="$HOME/Projects/noctalia-runtime"
export NOCTALIA_ASSETS_DIR="$runtime/assets"
exec "$runtime/build/noctalia" "$@"
SH
chmod +x "$HOME/.local/bin/noctalia"
export PATH="$HOME/.local/bin:$PATH"
noctalia --version
```

## Cài dotfiles

```sh
git clone https://github.com/blablabla0972/dotfiles.git "$HOME/Projects/dotfiles"
cd "$HOME/Projects/dotfiles"
./install.sh --dry-run --no-state
./install.sh --no-state
noctalia config validate
```

`--no-state` giữ session/lock settings hiện có. Cài riêng `noctalia` không có
cờ đó chỉ khi muốn lấy state của snapshot. Các file bị thay được backup trong
`~/.config/backups/`; giữ backup cho tới khi desktop mới được kiểm tra.
Backup mới giữ nguyên đường dẫn tương đối trong HOME: ví dụ
`dotfiles-<timestamp>-<id>/.config/kitty`, `.local/bin/<script>` hoặc
`.local/state/noctalia/settings.toml`; các backup cũ không bị chuyển đổi.
Khi khôi phục, kiểm tra đúng bản backup và đường dẫn đích, bỏ riêng symlink do
installer tạo ở đích đó rồi chuyển mục backup về vị trí ban đầu. Không copy
đệ quy lên các symlink còn trỏ vào repo, vì thao tác đó có thể sửa source thay
vì khôi phục file riêng của máy.
Pipeline gọi tên tương thích `swww`/`swww-daemon`. Nếu máy mới cài `awww`,
chuẩn bị alias executable mà không ghi đè command sẵn có:

```sh
command -v swww >/dev/null || ln -s "$(command -v awww)" "$HOME/.local/bin/swww"
command -v swww-daemon >/dev/null || ln -s "$(command -v awww-daemon)" "$HOME/.local/bin/swww-daemon"
```

Mặc định installer không chọn snapshot systemd; trên máy mới, xem trước các
unit trước khi cài:

```sh
./install.sh --dry-run --no-state systemd
./install.sh --no-state systemd
```

Không bật Hermes hoặc các unit snapshot khác nếu chưa chuẩn bị runtime của chúng.
Chuẩn bị wallpaper thật trước khi đăng nhập. Sau đó đăng nhập vào phiên Hyprland
đã cấu hình; autostart sẽ mở Noctalia nếu chưa chạy và giữ chính sách khóa khi
khởi động hiện có. Đảm bảo wallpaper daemon cũng đang chạy trong phiên này,
rồi bật riêng wallpaper daemon và kiểm tra IPC trước khi chạy owner giao dịch:

```sh
systemctl --user daemon-reload
systemctl --user enable --now swww-daemon.service
noctalia msg status
hyprctl configerrors
python3 ~/.config/hypr/scripts/generate-theme.py --apply-wallpaper /path/to/wallpaper.jpg
hyprctl reload config-only
hyprctl configerrors
```

Các lệnh IPC và apply chỉ chạy trong phiên desktop sau khi compositor, Noctalia
và wallpaper daemon sẵn sàng. Không khởi động thêm shell hoặc hypridle song song.
Tài liệu build v5.2.1 trong repo redesign là lịch sử, không phải pin hiện tại.

## Bằng chứng và giới hạn

Ngày 2026-11-07: source đã được đẩy và xác nhận bằng `git ls-remote`; build
native trên máy hiện tại thành công. Setup không dùng bundle cục bộ đã tái hiện
lỗi thiếu `nlohmann_json`, vì vậy các dependency trên là bắt buộc, không phải
đã được installer cung cấp. Chưa thử cài lại trên một hệ điều hành sạch.
Áp lại wallpaper hiện tại đã nhận JSON `status=applied`, Noctalia config hợp lệ,
Hyprland reload không báo lỗi và không có user unit failed. Không ép khóa hoặc
suspend trong phiên làm việc để kiểm tra.

Cú pháp build đối chiếu với [Meson Running Meson](https://mesonbuild.com/Running-Meson.html).
