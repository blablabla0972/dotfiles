# Quickshell Desktop Shell Migration Design Specification

**Date**: 2026-11-12  
**Target Repository**: `https://github.com/blablabla0972/dotfiles`  
**Branch**: `quickshell` (worktree: `.worktrees/quickshell`)  
**Scope**: Replace *only* Noctalia desktop shell with a custom Quickshell QML shell (Top Bar + Dynamic Island + Brain_Shell-style Control Center). Keep Hyprland Lua, compositor settings, UWSM, fcitx5, swww-daemon, Quickshell wallpaper-switcher, Matugen, and Quiet Current theme engine.

---

## 1. Verified / Assumed / Blocked Matrix

| Category | Item | Status | Evidence / Source |
| :--- | :--- | :---: | :--- |
| **Compositor** | Hyprland 0.57.0 with Lua configuration frontend (`hyprland.lua`) | **VERIFIED** | `hyprctl version`, `configerrors` is clean (0 errors), PID 945 running via UWSM |
| **Shell Engine** | Quickshell 0.3.2 installed on Arch Linux host | **VERIFIED** | `/usr/bin/qs`, `/usr/bin/quickshell`, Qt 6.8+ QML modules in `/usr/lib/qt6/qml/Quickshell/` |
| **Current Shell** | Noctalia v5.4.1 patched C++23 build running | **VERIFIED** | PID 1019, launcher `/home/admin/.local/bin/noctalia` pointing to custom build |
| **Wallpaper** | `swww-daemon 0.12.1` active systemd user service | **VERIFIED** | PID 1233, `systemctl --user status swww-daemon.service` running on layer bottom |
| **Carousel** | `config/quickshell/wallpaper-switcher/` is existing Quickshell module | **VERIFIED** | Retained untouched; `shell.qml`, `ApplyState.js`, `apply-wallpaper.sh` verified |
| **Security/Lock** | `hypridle` v0.1.8 and `hyprlock` v0.9.7 installed | **VERIFIED** | Binaries verified; existing `hypridle.conf` audited and gaps identified |
| **D-Bus Name** | `org.freedesktop.Notifications` currently owned by Noctalia | **VERIFIED** | `busctl --user get-name-owner org.freedesktop.Notifications` returns PID 1019 |
| **Tests Baseline** | Existing test suite passing | **VERIFIED** | 219/219 unit tests passing (`Ran 219 tests in 29.265s, OK`), `validate.py` 0 errors |
| **Hardware** | Display `eDP-1` 1920x1080 @ 144Hz, Intel UHD Graphics | **VERIFIED** | `hyprctl monitors -j`, Linux 7.3.1-1-cachyos kernel |
| **Cutover Approval**| Live replacement of Noctalia on main session | **BLOCKED** | Gated on explicit user consent; no live cutover until user approves |

---

## 2. Clean-Room Provenance & Architectural Boundaries

Based on the audit of 8 reference repositories (`docs/quickshell/REFERENCE_AUDIT.md`):
1. **Zero Verbatim Code Copying**:
   - `Brainitech/Brain_Shell` is **AGPL-3.0**. Its 3-column layout and tab navigation are adopted as visual design inspiration, but all QML code is written cleanly from scratch.
   - `enhaoswen/Tide-island` and `caelestia-dots/shell` are **GPL-3.0**. Only architectural patterns are referenced.
   - `selvarn/NotchShell` is **unlicensed (All Rights Reserved)**. Zero code copying.
2. **Mathematical Derivations**:
   - Smooth concave anti-corners at the top bezel of the Dynamic Island are derived independently using `PathCubic` Bézier curves matching the screen border radius.
   - Dynamic Island state transitions use an independent declarative priority queue in pure QML/JS.
3. **No Heavy Daemons / Polling**:
   - No external bash daemons piping JSON into QML (avoiding `lunanoir21`'s `backend.sh`).
   - No 5-second polling loops or shell outs for `$HOME` (avoiding `Brain_Shell` anti-patterns).
   - Use native `Quickshell.Services` (`Pipewire`, `Mpris`, `UPower`, `SystemTray`, `Bluetooth`, `Networking`) and `Quickshell.Hyprland`.

---

## 3. Architecture & Window Layering Model

```text
Hyprland Lua 0.57.0 (Window Management, Tiling, Animations)
  │
  ├── Quickshell rice-shell (Single Main Shell Process)
  │   ├── Bar (PanelWindow, Layer.Top, ExclusiveZone: 40)
  │   │   ├── Left: Workspaces (Quickshell.Hyprland) + Launcher Pill
  │   │   ├── Center: Dynamic Island Host (aligned with Island surface)
  │   │   └── Right: Status, Tray (SystemTray), Media Pill, Clock
  │   │
  │   ├── Dynamic Island (PanelWindow, Layer.Overlay, ExclusiveZone: 0)
  │   │   ├── Convex/Concave Bezel Shape (ShapePath + PathCubic anti-corners)
  │   │   ├── Morphing States: idle | media | volume/brightness | notification | expanded
  │   │   ├── Dynamic Input Region: mask: Region { item: activeShape } (prevents click swallowing)
  │   │   └── Priority State Machine: k4-style numeric alert precedence
  │   │
  │   ├── Control Center (PanelWindow, Layer.Overlay, ExclusiveZone: 0)
  │   │   ├── Header Pill Tabs: Home | System | Apps | Config
  │   │   ├── Home Tab 3-Column Responsive Grid (~950px max width):
  │   │   │   ├── Left Column: Profile Card + Calendar (~210px)
  │   │   │   ├── Center Column: Big Clock + Media Player (~450px)
  │   │   │   └── Right Column: Brightness Slider + 2-Column Quick Toggles (~210px)
  │   │   ├── Scrim backdrop with click-away dismissal & Esc handler
  │   │   └── Focus Policy: WlrKeyboardFocus.OnDemand (no focus stealing)
  │   │
  │   ├── App Launcher (PanelWindow, Layer.Overlay, ExclusiveZone: 0)
  │   │   ├── Desktop entries search & execution via uwsm app --
  │   │   └── Esc / outside-click dismissal
  │   │
  │   ├── NotificationServer & OSD (Layer.Overlay)
  │   │   └── Guarded in shell.qml via Loader { active: Quickshell.env("ENABLE_NOTIFICATIONS") === "1" }
  │   │       Tested via dbus-run-session during M6; live session binding occurs only at M9 cutover
  │   │
  │   └── Shared Native Services (Mpris, Pipewire, UPower, SystemTray, Bluetooth, Network)
  │
  ├── Wallpaper Subsystem (Preserved 100%)
  │   ├── Quickshell wallpaper-switcher (SUPER+W)
  │   ├── swww-daemon (systemd user service)
  │   └── generate-theme.py (decoupled mode, no Noctalia dependency)
  │
  └── Safety-Critical Integrations
      ├── hypridle (180s dim 20%, 300s lock, 360s DPMS, 1800s suspend; unlock_cmd restore)
      │   └── DPMS commands use Hyprland Lua syntax: hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
      └── hyprlock (ext-session-lock-v1; Super+L fallback to direct pidof hyprlock || hyprlock)
```

---

## 4. Component Structure & Directory Layout

```text
config/quickshell/rice-shell/
  ├── shell.qml                  # ShellRoot, Variants across Quickshell.screens, IpcHandler "rice", conditional Notifications Loader
  ├── bar/
  │   ├── Bar.qml                # PanelWindow top bar with exclusiveZone: 40
  │   ├── Workspaces.qml         # Hyprland.workspaces integration with active/urgent badges
  │   ├── StatusTray.qml         # SystemTray items + power/battery/network indicators
  │   └── Clock.qml              # Formatted local time/date pill
  ├── island/
  │   ├── Island.qml             # Morphing Dynamic Island window & overlay
  │   ├── IslandShape.qml        # Shape with PathCubic anti-corners blending to screen top
  │   └── IslandState.js         # Alert precedence state machine & auto-collapse timer
  ├── dashboard/
  │   ├── Dashboard.qml          # Control Center popup window with modal scrim & tabs
  │   ├── Home.qml               # 3-column Brain_Shell-style responsive grid
  │   ├── ProfileCard.qml        # User avatar & greeting
  │   ├── CalendarCard.qml       # Month calendar view
  │   ├── ClockCard.qml          # Large format digital clock
  │   ├── PlayerCard.qml         # MPRIS track title, artist, art & playback buttons
  │   └── QuickSettings.qml      # Brightness slider + 2-col quick toggle grid
  ├── launcher/
  │   └── Launcher.qml           # Searchable application launcher
  ├── overlays/
  │   └── Notifications.qml      # Freedesktop notification popup toasts & history (loaded conditionally)
  ├── services/
  │   ├── Audio.qml              # Pipewire sink/source helper
  │   ├── Media.qml              # Mpris playback helper
  │   └── Theme.qml              # Reads adaptive-theme.json tokens with contrast fallbacks
  └── theme/
      └── Tokens.qml             # Semantic color roles & material opacity bindings
```

---

## 5. Shell IPC Contracts (`rice`)

Public IPC endpoint registered via `IpcHandler { target: "rice" }`:
- `health`: Returns JSON `{ "status": "ok", "version": "1.0.0", "screens": [...] }`
- `toggleLauncher`: Toggles App Launcher visibility
- `toggleDashboard [tab]`: Toggles Control Center (optionally selecting tab: home, system, apps, config)
- `toggleNotifications`: Toggles Notification Center / history panel
- `toggleSession`: Toggles Session power menu
- `volumeUp`, `volumeDown`, `volumeMute`: Adjusts default PipeWire audio sink
- `brightnessChanged`: Updates brightness OSD

Tested directly via CLI:
```bash
qs ipc -p <path>/config/quickshell/rice-shell call rice health
```

---

## 6. Theme Pipeline Decoupling Contract

`generate-theme.py` will support `--backend {auto,quickshell,noctalia}`:
1. When `--backend quickshell` is active (or detected when `noctalia` is inactive/missing):
   - Invokes `matugen` directly to generate `hypr/colors.conf`, `noctalia/palettes/matugen.json`, and `micro/colorschemes/adaptive.micro`.
   - Derives semantic tokens via `derive_tokens.py` directly from `matugen.json` without `noctalia theme` CLI.
   - Synchronizes GTK 3/4, Qt 5/6, and `gsettings`.
   - Generates `hypr/noctalia.lua` directly from derived tokens so `hyprland.lua` retains full theme parity.
   - Emits schema v1 JSON receipt on `stdout`.
   - Bypasses `quiesce_shell()` / `restart_shell()` Noctalia calls.
   - Rollback restores snapshot, reverts `swww`, and reloads Hyprland safely.
