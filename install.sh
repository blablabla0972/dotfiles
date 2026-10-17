#!/usr/bin/env bash
# =============================================================================
# Dotfiles installer — tạo symlink từ repo về ~/.config
# Cách dùng:
#   ./install.sh           # cài hết
#   ./install.sh hypr noctalia # chỉ cài vài mục
#   ./install.sh --dry-run # xem sẽ làm gì, chưa làm thật
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$REPO/config"
ROOT_SRC="$REPO/root"
TARGET="$HOME/.config"
BACKUP_DIR="$TARGET/backups/dotfiles-$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
ONLY=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) ONLY+=("$arg") ;;
    esac
done

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
backup(){ echo -e "${YELLOW}[BACKUP]${NC} $1"; }

run() { if [ "$DRY_RUN" -eq 1 ]; then echo "DRY: $*"; else "$@"; fi; }

# --- symlink một mục -------------------------------------------------------
link() {
    local src="$1" dst="$2"

    # Nếu đã là symlink đúng rồi thì bỏ qua
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        ok "đã link sẵn: $dst"
        return
    fi

    # Nếu target đã tồn tại (thường) thì backup trước
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        run mkdir -p "$BACKUP_DIR"
        backup "$dst → $BACKUP_DIR/"
        run mv -T "$dst" "$BACKUP_DIR/$(basename "$dst")"
    fi

    run mkdir -p "$(dirname "$dst")"
    run ln -sT "$src" "$dst"
    ok "linked: $dst → $src"
}

# --- main ------------------------------------------------------------------
info "Repo: $REPO"
info "Target: $TARGET"
[ "$DRY_RUN" -eq 1 ] && info "(dry-run — chưa thay đổi gì)"
echo

run mkdir -p "$TARGET"

# 1) Các thư mục con → ~/.config/<tên>
for src in "$CONFIG_SRC"/*/; do
    name="$(basename "$src")"
    if [ "${#ONLY[@]}" -gt 0 ]; then
        skip=1
        for o in "${ONLY[@]}"; do [ "$o" = "$name" ] && skip=0 && break; done
        [ "$skip" -eq 1 ] && continue
    fi
    link "${src%/}" "$TARGET/$name"
done

# 2) Các file lẻ → ~/.config/<tên-file>
for src in "$ROOT_SRC"/*; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    if [ "${#ONLY[@]}" -gt 0 ]; then
        skip=1
        for o in "${ONLY[@]}"; do [ "$o" = "$name" ] && skip=0 && break; done
        [ "$skip" -eq 1 ] && continue
    fi
    link "$src" "$TARGET/$name"
done

# 3) File state → ~/.local/state/<tên-app>/<file>  (mục chọn theo tên app, vd: "noctalia")
STATE_SRC="$REPO/state"
STATE_TARGET="$HOME/.local/state"
if [ -d "$STATE_SRC" ]; then
    for app_src in "$STATE_SRC"/*/; do
        [ -d "$app_src" ] || continue
        app="$(basename "$app_src")"
        if [ "${#ONLY[@]}" -gt 0 ]; then
            skip=1
            for o in "${ONLY[@]}"; do [ "$o" = "$app" ] && skip=0 && break; done
            [ "$skip" -eq 1 ] && continue
        fi
        for src in "$app_src"*; do
            [ -e "$src" ] || continue
            link "$src" "$STATE_TARGET/$app/$(basename "$src")"
        done
    done
fi

echo
ok "Xong. Backup (nếu có) nằm trong: $BACKUP_DIR"
echo
info "Các symlink KHÔNG hoạt động trên máy khác cần tạo lại thủ công:"
info "  ~/.config/hypr/current_wallpaper → ảnh trong ~/Ảnh/Wallpaper"
info "  ~/.config/hypr/gpu/{intel,nvidia} → /dev/dri/by-path/..."
