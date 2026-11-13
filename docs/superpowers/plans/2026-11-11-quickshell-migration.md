# Quickshell Desktop Shell Migration Plan (M0…M10)

**Date**: 2026-11-12  
**Target Branch**: `quickshell` (worktree: `.worktrees/quickshell`)  
**Parent / Baseline**: `main` (commit `f20a20a4ba10cd8c604dabbf3c4aa5e5b9db7c30`)

---

## Milestone Execution Roadmap

| Milestone | Scope & Deliverables | Primary Files | Verification Command | Exit Code | Gate Conditions |
| :---: | :--- | :--- | :--- | :---: | :--- |
| **M0** | Audit, inventory, baseline tests | *None (Read-Only)* | `python3 tests/validate.py` & unit tests | 0 | Baseline 219 tests pass; live inventory documented (COMPLETED) |
| **M1** | Isolated worktree & design specs | `docs/superpowers/*`, `docs/quickshell/*` | `git branch --show-current` | 0 | Independent review approves spec & clean-room rules (COMPLETED) |
| **M2** | Quickshell minimal root + theme view | `rice-shell/shell.qml`, `theme/Tokens.qml`, `bar/Bar.qml` | `qs -p config/quickshell/rice-shell --dry-run` | 0 | `rice health` IPC responds; reads `adaptive-theme.json` (COMPLETED) |
| **M3** | Top Bar + Dynamic Island MVP | `rice-shell/island/`, `bar/Workspaces.qml`, `bar/StatusTray.qml` | IPC toggle tests, region mask check | 0 | 5 states work (`idle`, `media`, `volume`, `notify`, `expanded`); no click trap (COMPLETED) |
| **M4** | Native Services (PipeWire & MPRIS) | `rice-shell/services/`, `rice-shell/island/Island.qml` | Audio/Media state tests | 0 | Volume/mute & media controls work without subprocess polling; Island owns OSD rendering (COMPLETED) |
| **M5** | Brain_Shell Control Center & Launcher | `rice-shell/dashboard/`, `rice-shell/launcher/` | UI layout rendering at 1920x1080 & 1366x768 | 0 | 3-col Home grid, pill tabs, search launcher, Esc dismiss (COMPLETED) |
| **M6** | Notifications & OSD parity | `rice-shell/overlays/Notifications.qml` | `dbus-run-session` isolated notification tests | 0 | Actions, history, auto-expire; conditional Loader; zero collision with Noctalia (COMPLETED) |
| **M7** | Safety-Critical Parity (Lock & Idle) | `config/hypr/hypridle.conf`, `config/hypr/config/binds.lua` | `hypridle -c ... -v` syntax test | 0 | 180s dim, 300s lock, 360s DPMS (Lua syntax), 1800s suspend; `Super+L` direct `pidof hyprlock \|\| hyprlock` (COMPLETED) |
| **M8** | Theme Pipeline Decoupling | `config/hypr/scripts/generate-theme.py`, `tests/` | RED-GREEN tests in `tests/test_adaptive_transaction.py` | 0 | Wallpaper transitions & rollback work without `noctalia` on PATH; 222/222 tests pass (COMPLETED) |
| **M9** | Controlled Cutover (USER APPROVAL ONLY) | `docs/quickshell/CUTOVER_ROLLBACK.md` | Service health, D-Bus single owner | 0 | User approved. Noctalia stopped cleanly, Quickshell PID 29296 + hypridle PID 29399 live (COMPLETED) |
| **M10**| Final Verification & Delivery | Full test suite, lint, docs | `python3 tests/validate.py` & unit tests | 0 | 222/222 tests pass; branch `quickshell` clean; `main` untouched (COMPLETED) |

---

## Detailed Milestone Execution Steps

### Milestone M0: Discovery & Baseline (COMPLETED)
- Verified active running environment: Hyprland 0.57.0 (Lua), Quickshell 0.3.2, Noctalia v5.4.1 (PID 1019), swww-daemon 0.12.1 (PID 1233).
- Ran baseline test suite: `python3 tests/validate.py` (0 errors) and `python3 -m unittest discover -s tests -v` (219/219 tests pass).
- Audited 8 reference repositories for licenses and architectural patterns.

### Milestone M1: Isolated Branch `quickshell` & Design Specs (COMPLETED)
- Created isolated git worktree `.worktrees/quickshell` on branch `quickshell`.
- Authored design specifications:
  - `docs/superpowers/specs/2026-11-11-quickshell-migration-design.md`
  - `docs/superpowers/plans/2026-11-11-quickshell-migration.md`
  - `docs/quickshell/REFERENCE_AUDIT.md`
  - `docs/quickshell/COMPATIBILITY_MATRIX.md`
  - `docs/quickshell/CUTOVER_ROLLBACK.md`
- Gate: Independent review completed, technical review findings addressed.

### Milestone M2: Quickshell Minimum Root + Theme View (COMPLETED)
- Scaffolded `config/quickshell/rice-shell/`:
  - `shell.qml`: `ShellRoot` with `Variants` over `Quickshell.screens`. Implements `IpcHandler { target: "rice" }` with `health`. Loads `Notifications.qml` conditionally via `Loader { active: Quickshell.env("ENABLE_NOTIFICATIONS") === "1" }`.
  - `theme/Tokens.qml`: Reads `$XDG_STATE_HOME/desktop-wallpaper/adaptive-theme.json` with fallback colors and WCAG contrast check.
  - `bar/Bar.qml`: Initial top bar rendering active workspace and time.
- Verified with `qs ipc -p ... prop get rice status` -> `ok`.

### Milestone M3: Top Bar + Dynamic Island MVP (COMPLETED)
- Implemented `rice-shell/island/`:
  - `Island.qml`: Layer surface with dynamic `mask: Region { item: islandShape }` to prevent click trapping.
  - `IslandShape.qml`: Convex/concave Bézier silhouette (`PathCubic`) blending to screen top bezel.
  - `IslandState.js`: 5 states (`idle`, `media`, `volume`, `notification`, `expanded`) with priority queue and auto-collapse timer.
- Integrated `bar/Workspaces.qml` (`Quickshell.Hyprland`) and `bar/StatusTray.qml` (`Quickshell.Services.SystemTray`).

### Milestone M4: Native Services (Audio & Media) (COMPLETED)
- Implemented `rice-shell/services/Audio.qml` using `Quickshell.Services.Pipewire` with `PwObjectTracker`.
- Implemented `rice-shell/services/Media.qml` using `Quickshell.Services.Mpris`.
- Implemented volume/brightness OSD HUD in Island with fast morphing and deduplicated dismiss timer.

### Milestone M5: Brain_Shell-Style Control Center & Launcher (COMPLETED)
- Implemented `rice-shell/dashboard/Dashboard.qml`:
  - Header pill tabs: Home, System, Apps, Config.
  - 3-column responsive Home tab (Profile+Calendar, Clock+Media, Brightness+Quick Toggles) matching Brain_Shell aesthetic.
  - Modal backdrop scrim with outside-click and Escape key dismissal.
  - Keyboard focus: `WlrKeyboardFocus.OnDemand`.
- Implemented `rice-shell/launcher/Launcher.qml`:
  - Searchable desktop entries with direct `DesktopEntry.execute()`.

### Milestone M6: Notifications & OSD Parity (COMPLETED)
- Implemented `rice-shell/overlays/Notifications.qml`:
  - Freedesktop notification server popup toasts and history view.
  - Loaded conditionally in `shell.qml` via `Loader { active: Quickshell.env("ENABLE_NOTIFICATIONS") === "1" }`.
  - Tested strictly inside `dbus-run-session` to prevent collision with running Noctalia D-Bus name.

### Milestone M7: Safety-Critical Parity (Lock & Idle) (COMPLETED)
- Updated `config/hypr/hypridle.conf`:
  - Timings: 180s dim (20%), 300s lock, 360s DPMS off, 1800s suspend.
  - Invariants: `lock_cmd = pidof hyprlock || hyprlock`, `before_sleep_cmd = loginctl lock-session`, `unlock_cmd = brightnessctl -r`.
  - DPMS dispatch syntax using Hyprland 0.57.0 Lua table:
    `after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'`
    `on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'`
    `on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'`
- Updated `config/hypr/config/binds.lua`:
  - Added robust direct fallback to `Super+L`: `pidof hyprlock || hyprlock`.

### Milestone M8: Theme Pipeline Decoupling (COMPLETED)
- Added RED-GREEN tests in `tests/test_adaptive_transaction.py` and `tests/test_theme_sync.py`:
  - Verified theme generation and rollback without `noctalia` on PATH.
- Refactored `config/hypr/scripts/generate-theme.py`:
  - Added `--backend {auto,quickshell,noctalia}` and `--mode {dark,light}`.
  - Ran Matugen and `derive_tokens.py` directly in Quickshell mode.
  - Generated `hypr/noctalia.lua` for full Hyprland theme parity.
  - Verified all 222 tests pass GREEN.

### Milestone M9: Controlled Cutover (COMPLETED)
- User explicitly approved cutover via interactive prompt.
- Quiesced Noctalia cleanly (PID 1019 exited, D-Bus `org.freedesktop.Notifications` released).
- Started Quickshell shell (PID 29296) and hypridle (PID 29399).
- Verified IPC health: `rice health` -> `status=ok screens=1 mode=dark`.
- Verified D-Bus ownership and live notifications via `notify-send`.

### Milestone M10: Final Verification & Branch Delivery (COMPLETED)
- Full test suite verified: 222/222 unit tests pass (`python3 -m unittest discover -s tests -v`).
- Repository validator verified: `python3 tests/validate.py` (0 errors).
- Compositor errors: `hyprctl configerrors` (0 errors).
- Git branch isolation: `quickshell` branch cleanly committed; `main` branch 100% pristine and untouched.

