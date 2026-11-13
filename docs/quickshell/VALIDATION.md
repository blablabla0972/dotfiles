# Quickshell Desktop Shell Migration — Comprehensive Validation Report

**Date**: 2026-11-12  
**Target Branch**: `quickshell`  
**Host Architecture**: CachyOS Linux x86_64 (`7.3.1-1-cachyos`)  
**Compositor**: Hyprland 0.57.0 (Lua frontend)  
**Shell Engine**: Quickshell 0.3.2 (Qt 6.9.3)  
**Idle & Lock**: hypridle v0.1.8, hyprlock v0.9.7  
**Status**: Historical validation snapshot from 2026-11-12; its test count and live-session status are not current verification.

---

## 1. Test Suite Execution & Exit Codes

### A. Python Unit Test Suite
Command:
```bash
python3 -m unittest discover -s tests -v
```
- **Total Tests**: 222
- **Failures**: 0
- **Errors**: 0
- **Duration**: 29.85s
- **Exit Code**: `0`

Key Test Coverage:
- `tests.test_adaptive_transaction`:
  * `test_quickshell_mode_applies_without_noctalia_on_path`: **PASS**
  * `test_quickshell_mode_rolls_back_without_restarting_noctalia`: **PASS**
  * `test_success_acknowledges_the_committed_palette_and_unicode_path`: **PASS**
  * `test_competing_processes_serialize_complete_palette_and_mode_commits`: **PASS**
- `tests.test_theme_sync`:
  * `test_theme_mode_changed_without_noctalia`: **PASS**
  * `test_mode_event_updates_outputs_and_preserves_wallpaper`: **PASS**
- `tests.test_theme_safety`: 14/14 tests **PASS**
- `tests.test_carousel`: 25/25 tests **PASS**

### B. Repository Validation Suite
Command:
```bash
python3 tests/validate.py
```
- **Exit Code**: `0`
- **Output**: 0 syntax/lint/schema errors across tracked dotfiles.

### C. Compositor Configuration Verification
Command:
```bash
hyprctl configerrors
```
- **Exit Code**: `0`
- **Output**: (empty - zero configuration errors).

---

## 2. Live Runtime Performance & Resource Usage

Collected via `ps -o pid,comm,%cpu,%mem,rss,vsz` on live session:

| Process | PID | CPU (%) | Memory (%) | RSS (KB) | VSZ (KB) | Role |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **`quickshell`** | 29296 | 0.6% | 2.8% | 223,980 | 1,012,948 | Top Bar, Dynamic Island, Control Center, SystemTray, PipeWire & MPRIS |
| **`hypridle`** | 30055 | 0.0% | 0.0% | 7,292 | 86,316 | 180s dim, 300s lock, 360s DPMS, 1800s suspend |
| **`swww-daemon`**| 1233 | 0.0% | 0.1% | 14,240 | 185,420 | Background wallpaper rendering daemon |

*Comparison against baseline Noctalia (PID 1019: ~1.2% CPU, ~280MB RSS): Quickshell demonstrates lower idle CPU usage and smaller steady-state memory footprint.*

---

## 3. Subagent Team Dispatch & Audit Trace

Dispatched 4 parallel research subagents and 1 independent reviewer:

1. **`CURRENT-DOTFILES-AUDITOR`** (`9200d5b4-60ee-4ec5-bd01-16b9fe750fd8`):
   - Audited active symlinks, Noctalia patched v5.4.1 assets, keybinds, and UWSM integration.
2. **`REFERENCE-RESEARCHER`** (`fc33f371-23f9-4365-827b-41b3cc9286cf`):
   - Cloned and inspected 8 reference repositories in clean-room scratch directory.
   - Identified AGPLv3 (`Brain_Shell`) and GPLv3 (`caelestia-dots/shell`, `Tide-island`) licenses, strictly enforcing clean-room implementation.
3. **`THEME-TRANSACTION-AUDITOR`** (`6cf43919-9683-4984-aea7-07bcf3fb2df6`):
   - Traced `generate-theme.py`, `derive_tokens.py`, and `matugen/config.toml`. Formulated decoupling strategy.
4. **`WAYLAND-SECURITY-QA`** (`2fc2ede9-83d4-4033-ac19-1bb8e0745286`):
   - Identified Hyprland 0.57.0 Lua dispatch syntax for DPMS (`hl.dsp.dpms({action = "off"})`).
   - Identified click-trap mitigation via layer surface `Region` masking.
5. **`SPEC-AND-RISK-REVIEWER`** (`27822f6a-762f-4200-a5ff-6a32f8f49a13`):
   - Conducted independent review of M1 specs. Raised 5 architectural findings, all addressed prior to code implementation.

---

## 4. Key Resolved Risks & Architectural Solutions

1. **Hyprland 0.57.0 Lua DPMS Syntax**:
   - `hyprctl dispatch dpms off` fails under Lua config frontend. Resolved by dispatching table argument:
     `hyprctl dispatch 'hl.dsp.dpms({action = "off"})'`.
2. **`loginctl lock-session` Chaining Trap**:
   - `loginctl lock-session || hyprlock` terminates on exit code 0 even when no lock handler is listening.
   - Resolved by using direct process check: `pidof hyprlock || hyprlock`.
3. **Wayland Transparent Layer Input Mask**:
   - Fullscreen transparent `PanelWindow` captures mouse clicks across the entire screen.
   - Resolved by bounding input region using `mask: Region { item: islandShape }` in `Island.qml`.
4. **PipeWire 0.3.2 Node Binding**:
   - Volume changes log unbound node error unless tracked.
   - Resolved by wrapping sink and source in `PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(Boolean) }`.
5. **D-Bus Notification Singleton Collision**:
   - Running Noctalia and Quickshell cannot both own `org.freedesktop.Notifications`.
   - Normal rice startup enables notifications. `shell.qml` uses `Loader { active: Quickshell.env("ENABLE_NOTIFICATIONS") !== "0" }`; isolated previews can set `ENABLE_NOTIFICATIONS=0`. Autostart checks the exact rice-shell config and `rice health` before falling back, and never starts Noctalia while an unhealthy rice instance still owns the service.

---

## 5. Rollback Verification

The rollback note in this 2026-11-12 snapshot is historical, not a current runbook. Its former broad process-kill example is omitted because it could stop the independent wallpaper switcher. Use the scoped procedure in `CUTOVER_ROLLBACK.md`; no rollback or live cutover was run for this worktree. Noctalia binaries, configs, launcher, and assets were not modified.
