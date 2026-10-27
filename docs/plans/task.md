| Task | Status | Evidence |
|---|---|---|
| Task 1: Installer & env safety (install.sh, wt-prep.sh, env-hyprland) | done | tests/test_installer.py: 3 tests pass |
| Task 2: Systemd user unit portability & relative symlinks | done | %h used, relative symlinks in .wants |
| Task 3: IPC exception handling, snapshot retention & GTK sync | done | generate-theme.py updated, snapshot retention active |
| Task 4: Unit test isolation & robustness | done | 19/19 tests pass, test_theme_sync & test_installer |
| Task 5: Wallpaper switcher error feedback | done | notify-send fallback on wallpaper apply failure |
| Task 6: Desktop helper scripts integration in bin/ | done | toggle-desktop, hotspot, hotspot-menu in bin/ |
| Task 7: Ponytail cleanups & privacy protection | done | dead files/curves/capsule removed, address sanitized |
| Task 8: Verification & Git push | done | 19 tests pass, matrix check pass, hyprctl 0 errors |
