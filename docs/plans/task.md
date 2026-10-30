| Task | Status | Evidence |
|---|---|---|
| Task 1: Installer & env safety (install.sh, wt-prep.sh, env-hyprland) | done | tests/test_installer.py: 3 tests pass |
| Task 2: Systemd user unit portability & relative symlinks | done | %h used, relative symlinks in .wants |
| Task 3: IPC exception handling, snapshot retention & GTK sync | done | generate-theme.py updated, snapshot retention active |
| Task 4: Unit test isolation & robustness | done | 19/19 tests pass, test_theme_sync & test_installer |
| Task 5: Wallpaper switcher error feedback | done | notify-send fallback on wallpaper apply failure |
| Task 6: Desktop helper scripts integration in bin/ | done | toggle-desktop, hotspot, hotspot-menu in bin/ |
| Task 7: Ponytail cleanups & privacy protection | done | dead files/curves/capsule removed, address sanitized |
| Task 8: Verification & Git push (Round 1) | done | commit 56dbd0b pushed |
| Round 2.1: Installer subshell bug & multiple conflict backup | done | tests/test_installer.py: 5 tests pass |
| Round 2.2: Separate Core Live Desktop from Snapshot (--all) | done | install.sh --all option & core live default |
| Round 2.3: Hotspot reconnect state preservation on failure | done | bin/hotspot preserves PREV_WIFI_FILE on failure |
| Round 2.4: XKB relative symlink (base -> evdev) | done | config/xkb/rules/base is relative |
| Round 2.5: Mask password input in hotspot-menu | done | bin/hotspot-menu rofi_cmd -password |
| Round 2.6: Wallpaper picker thumbnail generation deferral | done | idle timer + renice/ionice idle priority |
| Round 2.7: Verification, installation & Git push (Round 2) | done | 21 tests pass, install.sh verified, pushed to GitHub |
| Round 3.1: Remove hotspot feature (scripts, binds, window rules) | done | bin/hotspot*, binds & window rules deleted |
| Round 3.2: Sanitize state/noctalia & decouple from default install | done | hardcoded wallpaper/monitor removed, CORE_STATES=() |
| Round 3.3: Verification, installation & Git push (Round 3) | done | 21 tests pass, hyprctl 0 errors, pushed to GitHub |
| Round 4.1: Clean up [widget.hotspot] from config/noctalia | done | config/noctalia/config.toml cleaned |
| Round 4.2: Portable color_scheme_path in qt6ct.conf | done | color_scheme_path=~/.config/qt6ct/colors/noctalia.conf |
| Round 4.3: Automatic cleanup of orphaned bin symlinks in install.sh | done | install.sh cleans deleted bin script links |
| Round 4.4: Documentation updates in README.md and AGENTS.md | done | README.md & AGENTS.md updated |
| Round 4.5: Verification, install and Git push (Round 4) | done | 22 tests pass, hyprctl 0 errors, pushed to GitHub |
| Audit 2026-10-30: Explore repository, live links, runtime, and checks | in progress | Live Noctalia/quickshell resolve to perf-panel-20261029; preserve existing work |
| Audit 2026-10-30: Clarify optimization constraints | done | User requests unchanged structure, appearance, effects, and keybindings |
| Audit 2026-10-30: Compare 2–3 scoped optimization approaches | pending | Base recommendations on reproduced faults and measured costs |
| Audit 2026-10-30: Present design and obtain approval | pending | Review before changing desktop behavior |
| Audit 2026-10-30: Record approved design | pending | docs/plans/2026-10-30-rice-audit-design.md |
| Audit 2026-10-30: Create implementation plan | pending | Transition after design approval |
