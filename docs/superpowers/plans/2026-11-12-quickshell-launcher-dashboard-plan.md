# Implementation Plan — Quickshell App Launcher & Dynamic Island Control Center

- **Branch**: `quickshell` (isolated in `.worktrees/quickshell`)
- **Baseline**: Quickshell 0.3.2, Hyprland 0.57.0 Lua, Matugen tokens
- **Invariants**: `main` untouched, no unneeded daemons, native-first Ponytail design

## Task 1: Complete App Launcher (`launcher/Launcher.qml`)
- Add category filter pills (All, Internet, Development, Multimedia, System, Settings) mapped to desktop entry categories.
- Zero-state view with pinned / quick-launch applications when search is empty.
- Full keyboard navigation: `Up`/`Down` arrow keys, `Tab`/`Backtab` category cycling, `Enter` execution, `Escape` dismissal.
- Command runner prefix (`> command` executes `kitty -e <command>`).
- Maintain glassmorphism styling and reactive `Tokens.qml` colors.

## Task 2: Dynamic Island Control Center (`dashboard/Dashboard.qml`, `island/Island.qml`, etc.)
- Restructure `dashboard/Dashboard.qml` from center modal to top-anchored dropdown (`anchors.top: true`).
- Use `IslandShape` with concave Bézier anti-corners at the top bezel.
- Dropdown height/width spring animation morphing down from the Dynamic Island.
- Tab views:
  - `Home`: ProfileCard, CalendarCard, ClockCard, PlayerCard, QuickSettings toggles.
  - `System`: Live telemetry (CPU, RAM, Uptime).
  - `Config`: Theme switcher, shell reload trigger.
- Integrate toggle handler in `island/Island.qml` so tapping the island or pressing `Super+X` drops down the Control Center.
- Outside scrim click and `Escape` dismisses back to compact island.

## Task 3: Wayland Integration, Tests & Final Verification
- Verify input regions (`mask: Region { item: ... }`) preventing transparent click blocking.
- Verify `WlrKeyboardFocus.OnDemand` for smooth focus acquisition and release.
- Run `pytest tests/` (all 222+ tests pass).
- Verify QML syntax and runtime loading with `qs ipc -p ~/.config/quickshell/rice-shell call rice health`.
- Commit changes cleanly on branch `quickshell`.
