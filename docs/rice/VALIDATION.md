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


## Quiet Current — 2026-10-28 (offline acceptance)

Branch `feat/quiet-current`, base `6b832a8`. Original baseline:44 tests, no skips.
Initial integrated suite:102 tests, zero failures/errors/skips; includes pure token math,
real transaction fault injection/rollback and three competing writer processes,
Unicode paths, state-preserving install, 50+ carousel selections/three apply
intentions, stale/duplicate/timeout replies, preview isolation and real offscreen
Quickshell Process acknowledgment/hash ordering. Real Matugen preview produced
five swatches with live generated-file hashes unchanged.

Native config validation:zero warnings/errors. Offline matrix:12 wallpaper
fixtures in both modes,192 native template renders, zero contrast failures;
minimum existing bar/terminal checks5.34:1, modeled native surfaces5.52:1.
Compositing remains an unverified sRGB model until actual pixel comparison;
these counts do not certify live contrast, HDR/HiDPI/multimonitor or FPS.

The palette transaction owns the new XDG state artifact, publishes it last,
and acknowledges only verified outcomes. Missing previous wallpaper or failed
restore cannot be reported as complete rollback. Installer `--no-state` protects
native session/lock settings during component preview. Source manifests,
known native binary/source differences and coverage are in
`QUIET_CURRENT_NATIVE_AUDIT.md`; API/schema in `ADAPTIVE_DESIGN_SYSTEM.md`.

Host baseline:Hyprland0.56.2 configerrors empty, eDP-1 1920x1080@144Hz scale1,
Noctalia dark/wallpaper/Matugen effective config. Single10s CPU/RSS sample and
private baseline image are recorded by `QUIET_CURRENT_STATE.md`; no automatic
performance governor or native C++ island has been enabled.

Live preview, screenshots and final merge acceptance are recorded below once
performed; offline acceptance alone is not completion of the desktop rollout.

Final review/fix suite:108 tests, zero failures/errors/skips. Recovery now verifies
Noctalia restart/readiness and post-rollback configerrors; malformed/failed restart
and persistent compositor errors cannot claim complete rollback. Derived-token
consumers require satisfied contrast diagnostics. Selected/default/all installer
state-preservation paths pass. Final matrix remains24 cases/192 renders/no failures.
Scoped source review approved; live execution is blocked by connector approval
policy and still requires user-terminal execution per APPLY_QUIET_CURRENT.md.


Live follow-up: permission blocker resolved; reviewed helper applied14 components
(including Micro) and the actual owner acknowledged success with coherent hashes.
Final109 tests pass without skips. Actual Wayland carousel preview/Esc-hide-pending/
ack/clean-exit and native launcher capture passed. Exact text pixels in launcher
screenshot measured7.75:1 selected and13.31:1 normal on this wallpaper/display.
Private evidence and remaining unavailable/conditional checks are documented in
QUIET_CURRENT_STATE.md. Preview is active; main merge still awaits user acceptance.

## Resumed caption cleanup and cache

Final121 tests,0 failures/errors/skips;24 matrix cases/192 renders/0 failures.
Native carousel probe confirms no idle/card text, five ready swatches, seven-card
geometry, navigation round-trip and clean exit. AGY terminal implementation was
reviewed by controller; AGY peer-reviewed the output cache (PASS).

Real Matugen cold/cache comparisons verify identical output and subprocess counts
1→0 for both the three-output renderer and five-swatch preview. One isolated CPU
sample measured673.23→10.10ms and678.68→9.81ms respectively; these are rendering
samples, not end-to-end apply/FPS claims. Cache corruption/unavailability, content
and configuration changes, generation races, symlinks and fresh request identity
are covered. Cache roots, ownership and private evidence are in the state ledger.
The user-selected worktree preview remains active; final visual/main acceptance
and previously unavailable live scenarios are not certified by these checks.
