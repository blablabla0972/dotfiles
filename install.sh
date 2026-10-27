#!/usr/bin/env bash
# =============================================================================
# Dotfiles installer — tạo symlink từ repo về ~/.config và ~/.local/bin
# Cách dùng:
#   ./install.sh           # cài hết
#   ./install.sh hypr noctalia # chỉ cài vài mục
#   ./install.sh --dry-run # xem sẽ làm gì, chưa làm thật
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

DRY_RUN=0
ONLY=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
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

# Lazy creation of unique backup directory
ACTUAL_BACKUP_DIR=""
get_backup_dir() {
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
    echo "$ACTUAL_BACKUP_DIR"
}

# --- symlink một mục -------------------------------------------------------
link() {
    local src="$1" dst="$2"

    # Nếu đã là symlink trỏ đúng đích rồi thì bỏ qua
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        ok "đã link sẵn: $dst"
        return
    fi

    # Nếu target đã tồn tại thì backup trước khi ghi đè
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local bdir
        bdir="$(get_backup_dir)"
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
    local name="$1"
    if [ "${#ONLY[@]}" -eq 0 ]; then
        return 0
    fi
    for o in "${ONLY[@]}"; do
        if [ "$o" = "$name" ]; then
            return 0
        fi
    done
    return 1
}

# --- main ------------------------------------------------------------------
info "Repo: $REPO"
info "Target: $TARGET"
[ "$DRY_RUN" -eq 1 ] && info "(dry-run — chưa thay đổi gì)"
echo

run mkdir -p "$TARGET"

# 1) Các mục trong config/ (thư mục hoặc file lẻ như starship.toml) → ~/.config/<tên>
if [ -d "$CONFIG_SRC" ]; then
    for src in "$CONFIG_SRC"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        should_install "$name" || continue
        link "${src%/}" "$TARGET/$name"
    done
fi

# 2) Các file lẻ trong root/ → ~/.config/<tên-file>
if [ -d "$ROOT_SRC" ]; then
    for src in "$ROOT_SRC"/*; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        should_install "$name" || continue
        link "$src" "$TARGET/$name"
    done
fi

# 3) File state → ~/.local/state/<tên-app>/<file>
if [ -d "$STATE_SRC" ]; then
    for app_src in "$STATE_SRC"/*/; do
        [ -d "$app_src" ] || continue
        app="$(basename "$app_src")"
        should_install "$app" || continue
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
        should_install "$name" || continue
        link "$src" "$BIN_TARGET/$name"
    done
fi

# 5) Reload systemd daemon nếu cấu hình systemd được cài
if [ "$DRY_RUN" -eq 0 ] && should_install "systemd"; then
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
