# Validation — 2026-10-17

- 10 stdlib transaction tests pass: mode switching, queued events, deduplication across modes, native-template failure rollback, GTK settings preservation, missing files, exited shell handling and concurrent user-mode preservation during wallpaper rollback. Test XDG directories are isolated.
- 12 real Matugen palettes and 96 native Noctalia template renders pass; generated Lua/TOML/GTK CSS parse. Solid semantic surfaces and the bar at 82% opacity and launcher at 221/255 opacity meet at least 6.43:1 foreground contrast in these fixtures.
- Rofi native parser passes all 12 cases. Installed Rofi 2.0.0-dirty crashes only in display_cleanup after its validation CLI; the check skips that cleanup with GDB while preserving the parser exit status. An invalid-syntax negative control was rejected. The normal launcher was also opened and captured successfully.
- Live Hyprland reload/configerrors and Noctalia validation pass at 1920×1080, scale 1.
- Live dark→light→dark hook synchronization verified across palette files, GTK preferences and native templates. Final/default mode is dark.
- Live wrapper wallpaper application and native wallpaper hook restoration verified with an identical image copy; original image and selection restored. Other hues are tested by the isolated rendering matrix.
- A real invalid-image transaction returns failure and preserves wallpaper, mode and output hashes.
- Kitty/Alacritty, launcher, dashboard, GTK Nautilus and Qt6ct previewed; a dedicated Kitty window enters/exits fullscreen correctly. Vietnamese glyphs render in both terminals. Native notification surface verified.
- Hyprlock card preview was rejected by the user. Final lock file restores the original layout exactly, except removal of the already-invalid general:grace option; authentication configuration is untouched. No further live lock/light-mode previews after the user correction.
- Screenshots, test logs and snapshots stay outside Git.

| Fixture | Dark minimum contrast | Light minimum contrast |
|---|---:|---:|
| cool | 7.7:1 | 6.43:1 |
| warm | 7.72:1 | 6.45:1 |
| green | 7.69:1 | 6.46:1 |
| muted | 7.7:1 | 6.45:1 |
| bright | 7.7:1 | 6.46:1 |
| busy | 7.69:1 | 6.45:1 |

## Review

Independent final review found two important issues: rollback could undo a newer user mode on ordinary settings files, and tests lacked temporary XDG_DATA_HOME. Both were reproduced/fixed; the concurrent-mode regression test passes, managed settings snapshots resolve the target without replacing the outer symlink, and test data stays temporary.

## Performance sample

Two-second idle samples, not a benchmark: Hyprland CPU 3.5%→2.5%, Noctalia 1.5%→2.5%; RSS 207.2→152.0 MiB and 191.4→184.6 MiB. No sustained regression observed during repeated native previews and fullscreen transitions.

## Glass correction

User follow-up identified insufficient glass: the bar was 92% opaque and the launcher surface was fully opaque. Bar opacity is now 82%; the launcher uses a Matugen-derived #RRGGBBDD surface (86.7%) with existing compositor blur. All 12 palette/parser cases pass at the actual configured opacity (minimum contrast 6.43:1); native launcher preview succeeds. Dark mode and the original lock layout are retained.

## Default Noctalia launcher glass

User screenshot showed the native Noctalia launcher, while the earlier glass change affected only the secondary Rofi launcher. The actual SUPER+SPACE bind invokes noctalia panel-toggle launcher. Corrected shell.panel.transparency_mode from solid to the supported glass enum; canonical config export confirms glass, native panel-open launcher creates the noctalia-panel surface, and a live screenshot confirms background translucency and compositor blur. This shared material also applies to other Noctalia popups. Dark mode and original Hyprlock layout remain unchanged.

Terminal glass: parsed Kitty config with its native loader and Alacritty TOML with tomllib; both report opacity .82. A fresh Kitty preview visibly showed wallpaper blur with opaque text (private screenshot terminal-glass.png); preview closed without restarting the user terminal.

Rofi removed on user request: package uninstalled; launcher configs, Matugen target, thumbnail generation and layer rule removed. Noctalia remains the SUPER+SPACE launcher.
Verified: 10 theme transaction tests, 12 isolated palette cases, shell syntax checks; package removal completed via Polkit authentication.
