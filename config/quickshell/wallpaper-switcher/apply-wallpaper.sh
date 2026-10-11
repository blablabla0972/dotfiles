#!/usr/bin/env bash
set -euo pipefail

# Serialize, validate, apply and verify in one foreground transaction.
# Noctalia remains the palette generator; awww remains the wallpaper backend.
exec python3 "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/generate-theme.py" --apply-wallpaper "${1:?Wallpaper path required}"
