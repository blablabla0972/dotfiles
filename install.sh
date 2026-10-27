#!/usr/bin/env bash
# =============================================================================
# Dotfiles installer — tạo symlink từ repo về ~/.config và ~/.local/bin
# Cách dùng:
#   ./install.sh           # cài các cấu hình desktop live mặc định
#   ./install.sh --all     # cài toàn bộ (gồm cả systemd và snapshot máy)
#   ./install.sh hypr btop # chỉ cài các mục được chọn
#   ./install.sh --dry-run # xem trước, chưa thay đổi thật
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$REPO/config"
ROOT_SRC="$REPO/root"
STATE_SRC="$REPO/state"
BIN_SRC="$REPO/bin"

TARGET="$HOME/.config"
STATE_TARGET="$HOME/.local/state"
BIN_TARGET="$HOME/.local/bin"

# Core live desktop targets (mặc định chỉ cài những mục này để đảm bảo tính an toàn & khả chuyển)
CORE_CONFIGS=(hypr noctalia quickshell matugen kitty alacritty gtk-3.0 gtk-4.0 qt5ct qt6ct btop starship.toml)
CORE_ROOTS=(kdeglobals)
CORE_STATES=()

DRY_RUN=0
INSTALL_ALL=0
ONLY=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --all)     INSTALL_ALL=1 ;;
        -h|--help)
            echo "Cách dùng: $0 [--dry-run] [--all] [mục1 mục2 ...]"
            echo "  Mặc định: Chỉ cài các cấu hình desktop live (${CORE_CONFIGS[*]} kdeglobals noctalia bin)."
            echo "  --all:    Cài toàn bộ cấu hình, bao gồm cả systemd và cấu hình riêng máy (snapshot)."
            echo "  --dry-run: Chỉ in thao tác dự kiến, không thay đổi file."
            exit 0
            ;;
        *) ONLY+=("$arg") ;;
    esac
done

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
backup() { echo -e "${YELLOW}[BACKUP]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()    { echo -e "${RED}[ERROR]${NC} $1" >&2; }

run() { if [ "$DRY_RUN" -eq 1 ]; then echo "DRY: $*"; else "$@"; fi; }

# Lazy creation of unique backup directory in current shell (tránh subshell làm mất biến)
ACTUAL_BACKUP_DIR=""
ensure_backup_dir() {
    if [ -z "$ACTUAL_BACKUP_DIR" ]; then
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        if [ "$DRY_RUN" -eq 1 ]; then
            ACTUAL_BACKUP_DIR="$TARGET/backups/dotfiles-$timestamp-dryrun"
        else
            mkdir -p "$TARGET/backups"
            ACTUAL_BACKUP_DIR="$(mktemp -d "$TARGET/backups/dotfiles-$timestamp-XXXXXX")"
        fi
    fi
}

# --- symlink một mục -------------------------------------------------------
link() {
    local src="$1" dst="$2"

    # Bỏ qua cùng file, kể cả khi thư mục cha là symlink
    if [ "$src" -ef "$dst" ]; then
        ok "đã link sẵn: $dst"
        return
    fi

    # Nếu target đã tồn tại thì backup trước khi ghi đè
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        ensure_backup_dir
        local bdir="$ACTUAL_BACKUP_DIR"
        run mkdir -p "$bdir"
        backup "$dst → $bdir/"
        local bdst="$bdir/$(basename "$dst")"
        if [ -e "$bdst" ] || [ -L "$bdst" ]; then
            bdst="$(mktemp -u "${bdir}/$(basename "$dst")-XXXXXX")"
        fi
        run mv -T "$dst" "$bdst"
    fi

    run mkdir -p "$(dirname "$dst")"
    run ln -sT "$src" "$dst"
    ok "linked: $dst → $src"
}

# --- kiểm tra tham số ONLY ------------------------------------------------
is_valid_target() {
    local target="$1"
    case "$target" in
        ''|.*|*/*) return 1 ;;
    esac
    [ -e "$CONFIG_SRC/$target" ] && return 0
    [ -e "$ROOT_SRC/$target" ] && return 0
    [ -e "$STATE_SRC/$target" ] && return 0
    [ -e "$BIN_SRC/$target" ] && return 0
    return 1
}

if [ "${#ONLY[@]}" -gt 0 ]; then
    invalid_targets=()
    for o in "${ONLY[@]}"; do
        if ! is_valid_target "$o"; then
            invalid_targets+=("$o")
        fi
    done
    if [ "${#invalid_targets[@]}" -gt 0 ]; then
        err "Mục cài không hợp lệ: ${invalid_targets[*]}"
        echo "Các mục hợp lệ có thể chọn:" >&2
        for d in "$CONFIG_SRC"/* "$ROOT_SRC"/* "$STATE_SRC"/* "$BIN_SRC"/*; do
            [ -e "$d" ] && echo "  - $(basename "$d")" >&2
        done
        exit 1
    fi
fi

should_install() {
    local category="$1" # config, root, state, bin
    local name="$2"

    # Nếu người dùng chỉ định cụ thể mục cần cài
    if [ "${#ONLY[@]}" -gt 0 ]; then
        for o in "${ONLY[@]}"; do
            [ "$o" = "$name" ] && return 0
        done
        return 1
    fi

    # Nếu chọn --all thì cài toàn bộ
    [ "$INSTALL_ALL" -eq 1 ] && return 0

    # Mặc định: Chỉ cài các thành phần Core Live Desktop
    case "$category" in
        bin) return 0 ;; # Toàn bộ script tiện ích máy bàn
        config)
            for c in "${CORE_CONFIGS[@]}"; do [ "$c" = "$name" ] && return 0; done
            return 1
            ;;
        root)
            for r in "${CORE_ROOTS[@]}"; do [ "$r" = "$name" ] && return 0; done
            return 1
            ;;
        state)
            for s in "${CORE_STATES[@]}"; do [ "$s" = "$name" ] && return 0; done
            return 1
            ;;
    esac
    return 1
}

# --- main ------------------------------------------------------------------
info "Repo: $REPO"
info "Target: $TARGET"
if [ "$INSTALL_ALL" -eq 1 ]; then
    info "Chế độ: Toàn bộ (bao gồm cả systemd và snapshot máy)"
elif [ "${#ONLY[@]}" -gt 0 ]; then
    info "Chế độ: Chọn lọc (${ONLY[*]})"
else
    info "Chế độ: Desktop Live mặc định (chạy './install.sh --all' nếu muốn liên kết cả systemd/snapshot)"
fi
[ "$DRY_RUN" -eq 1 ] && info "(dry-run — chưa thay đổi gì)"
echo

run mkdir -p "$TARGET"

# 1) Các mục trong config/ → ~/.config/<tên>
if [ -d "$CONFIG_SRC" ]; then
    for src in "$CONFIG_SRC"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        should_install "config" "$name" || continue
        link "${src%/}" "$TARGET/$name"
    done
fi

# 2) Các file lẻ trong root/ → ~/.config/<tên-file>
if [ -d "$ROOT_SRC" ]; then
    for src in "$ROOT_SRC"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        should_install "root" "$name" || continue
        link "$src" "$TARGET/$name"
    done
fi

# 3) File state → ~/.local/state/<tên-app>/<file>
if [ -d "$STATE_SRC" ]; then
    for app_src in "$STATE_SRC"/*/; do
        [ -d "$app_src" ] || continue
        app="$(basename "$app_src")"
        should_install "state" "$app" || continue
        for src in "$app_src"*; do
            [ -e "$src" ] || continue
            link "$src" "$STATE_TARGET/$app/$(basename "$src")"
        done
    done
fi

# 4) Desktop scripts → ~/.local/bin/<tên-script>
if [ -d "$BIN_SRC" ]; then
    run mkdir -p "$BIN_TARGET"
    for src in "$BIN_SRC"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        should_install "bin" "$name" || continue
        link "$src" "$BIN_TARGET/$name"
    done

    # Dọn các symlink mồ côi trong ~/.local/bin từng trỏ vào repo bin/ nhưng file nguồn đã bị xóa
    if [ -d "$BIN_TARGET" ]; then
        for dst in "$BIN_TARGET"/*; do
            if [ "${#ONLY[@]}" -gt 0 ]; then
                name="$(basename "$dst")"
                [ -e "$BIN_SRC/$name" ] && should_install "bin" "$name" || continue
            fi
            if [ -L "$dst" ]; then
                target_path="$(readlink "$dst" 2>/dev/null || true)"
                if [[ "$target_path" == "$BIN_SRC/"* ]] && [ ! -e "$dst" ]; then
                    if [ "$DRY_RUN" -eq 1 ]; then
                        info "DRY: rm -f $dst (symlink mồ côi)"
                    else
                        rm -f "$dst"
                        warn "Đã dọn symlink mồ côi: $dst"
                    fi
                fi
            fi
        done
    fi
fi

# 5) Reload systemd daemon nếu cấu hình systemd được cài
if [ "$DRY_RUN" -eq 0 ] && should_install "config" "systemd"; then
    if [ -d "/run/user/$(id -u)/systemd" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        info "Đã reload systemd user daemon."
    fi
fi

echo
if [ -n "$ACTUAL_BACKUP_DIR" ] && [ -d "$ACTUAL_BACKUP_DIR" ]; then
    ok "Xong. Backup nằm trong: $ACTUAL_BACKUP_DIR"
else
    ok "Xong. Tất cả symlink đã được đồng bộ."
fi
echo
info "Các symlink KHÔNG hoạt động trên máy khác cần tạo lại thủ công:"
info "  ~/.config/hypr/current_wallpaper → ảnh trong ~/Ảnh/Wallpaper"
info "  ~/.config/hypr/gpu/{intel,nvidia} → /dev/dri/by-path/..."
