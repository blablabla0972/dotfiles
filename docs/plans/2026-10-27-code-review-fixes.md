# Code Review Fixes Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Address and fix all code review findings across installer safety, systemd unit portability, IPC error handling, test isolation, user feedback, script tracking, and repository simplifications.

**Architecture:** 
- Fix installer concurrency/clobbering with unique lazy mktemp backup directories and selector validation.
- Make systemd user units portable across machines using `%h` specifiers and relative symlinks.
- Standardize IPC error handling across `generate-theme.py`, add snapshot retention, and make GTK icon tests independent of host environment.
- Add desktop notification error reporting on wallpaper switcher failure.
- Track missing desktop scripts in `bin/` with `install.sh` support.
- Apply Ponytail simplifications: remove dead reference configs/scripts, remove unreferenced animation curves, prune unused capsule groups, and sanitize private location data.

**Tech Stack:** Bash, Python 3, Hyprland Lua, Noctalia TOML, Systemd user units, Quickshell QML.

---

### Task 1: Fix Installer Backup Clobbering, Selector Validation, and Systemd Reload (`install.sh`, `wt-prep.sh`, `config/uwsm/env-hyprland`)

**Files:**
- Modify: `install.sh`
- Modify: `wt-prep.sh`
- Modify: `config/uwsm/env-hyprland`
- Test: Manual reproduction test in `/tmp/test-install`

**Step 1: Write a reproduction test script for installer backup clobbering and invalid selector**
Verify that running install twice in rapid succession in a test dir no longer destroys the original backup.

**Step 2: Update `install.sh`**
- Lazy initialize `BACKUP_DIR` using `mktemp -d "$TARGET/backups/dotfiles-$(date +%Y%m%d-%H%M%S)-XXXXXX"` only when a file needs to be moved.
- Protect against clobbering if a file already exists in `BACKUP_DIR`.
- Only print backup message if a backup was actually performed.
- Validate items in `ONLY`: if an item is not found in `CONFIG_SRC`, `ROOT_SRC`, `STATE_SRC`, or `BIN_SRC`, exit with code 1 and error message.
- Add `BIN_SRC="$REPO/bin"` to link scripts into `~/.local/bin/`.
- Call `systemctl --user daemon-reload` if systemd units are updated and user daemon is active.

**Step 3: Update `wt-prep.sh`**
- Check that `config/hypr/current_wallpaper` and `config/hypr/gpu` exist before removing targets and copying.
- Print clear warning if source file is missing rather than failing silently or wiping target.

**Step 4: Update `config/uwsm/env-hyprland`**
- Guard `AQ_DRM_DEVICES` export with `[ -e "$HOME/.config/hypr/gpu/intel" ]`.

---

### Task 2: Systemd User Unit Portability & Relative Symlinks (`config/systemd/user/`)

**Files:**
- Modify: `config/systemd/user/swww-daemon.service`
- Modify: `config/systemd/user/hermes-gateway.service`
- Modify: `config/systemd/user/graphical-session.target.wants/swww-daemon.service`
- Modify: `config/systemd/user/default.target.wants/hermes-gateway.service`

**Step 1: Replace hardcoded `/home/admin` with `%h` in service units**
- In `swww-daemon.service`: change `/home/admin/.local/bin/swww-daemon` to `%h/.local/bin/swww-daemon` (or binary name).
- In `hermes-gateway.service`: change `/home/admin` references to `%h`.

**Step 2: Convert absolute symlinks in `.wants` directories to relative symlinks**
- `graphical-session.target.wants/swww-daemon.service` -> `../swww-daemon.service`
- `default.target.wants/hermes-gateway.service` -> `../hermes-gateway.service`

---

### Task 3: IPC Exception Handling, Snapshot Retention & GTK Settings Sync (`config/hypr/scripts/generate-theme.py`)

**Files:**
- Modify: `config/hypr/scripts/generate-theme.py`
- Test: `tests/test_theme_sync.py`

**Step 1: Fix IPC exception catching**
- In `palette_for` (lines 111-115): catch `(RuntimeError, subprocess.SubprocessError, OSError)` when running `noctalia msg theme-mode-get`.
- In `wait_for_templates` (lines 235-242): catch `(RuntimeError, subprocess.SubprocessError, OSError)` so IPC errors during daemon reload don't prematurely abort the retry loop.

**Step 2: Add snapshot retention in `Snapshot.__init__`**
- List existing directories in `state_dir / 'desktop-wallpaper/backups'`.
- Sort by modification time and delete oldest entries if count exceeds retention limit (e.g., max 15 snapshots).

**Step 3: Make icon theme sync robust in `sync_toolkit_settings`**
- Search both `/usr/share/icons`, `~/.local/share/icons`, and XDG icon paths, or keep current icon theme if directory check fails.

---

### Task 4: Unit Test Isolation & Robustness (`tests/test_theme_sync.py`)

**Files:**
- Modify: `tests/test_theme_sync.py`
- Test: Run `python3 -m unittest discover -s tests -v`

**Step 1: Ensure GTK4 icon test has isolated fixture and doesn't fail on hosts without Papirus**
- In `test_theme_sync.py`: Provide mock/fixture for icon directories or pre-populate initial settings so `test_mode_event_updates_gtk_preferences_without_losing_user_settings` passes deterministically in any CI/container environment.

**Step 2: Add test for Noctalia IPC resilience**
- Test that `generate-theme.py` handles transient IPC errors gracefully during mode query and template waiting.

---

### Task 5: Wallpaper Switcher Error Feedback (`config/quickshell/wallpaper-switcher/apply-wallpaper.sh`)

**Files:**
- Modify: `config/quickshell/wallpaper-switcher/apply-wallpaper.sh`

**Step 1: Update `apply-wallpaper.sh`**
- Wrap `generate-theme.py --apply-wallpaper` call in error handling.
- On failure, send desktop notification via `notify-send -u critical` with the error summary.

---

### Task 6: Track Desktop Helper Scripts in `bin/` (`bin/`)

**Files:**
- Create: `bin/toggle-desktop`
- Create: `bin/hotspot`
- Create: `bin/hotspot-menu`
- Modify: `install.sh`
- Modify: `AGENTS.md`, `README.md`

**Step 1: Copy scripts from `~/.local/bin/` to `bin/` in repo**
- Ensure executable permissions (`chmod +x`).

**Step 2: Update `install.sh` to install `bin/` into `~/.local/bin/`**
- Link files from `REPO/bin/*` to `~/.local/bin/*`.

---

### Task 7: Ponytail Cleanups & Privacy Protection

**Files:**
- Delete: `config/hypr/hyprland.conf` (dead reference file)
- Delete: `config/hypr/scripts/hyprlock.sh` (unused script)
- Delete: `config/hypr/scripts/test_awww.sh` (unused benchmark)
- Modify: `config/hypr/config/animations.lua` (remove 3 unused curves)
- Modify: `config/noctalia/config.toml` (remove unreferenced `hardware` capsule group)
- Modify: `state/noctalia/settings.toml` (sanitize personal address)

**Step 1: Remove dead files**
- Delete `config/hypr/hyprland.conf`, `config/hypr/scripts/hyprlock.sh`, `config/hypr/scripts/test_awww.sh`.

**Step 2: Remove unreferenced curves in `animations.lua`**
- Remove `easeInOutCubic`, `linear`, `almostLinear`.

**Step 3: Remove unused `hardware` capsule group in `noctalia/config.toml`**
- Delete unreferenced `[[bar.default.capsule_group]]` `id = "hardware"`.

**Step 4: Sanitize location data in `state/noctalia/settings.toml`**
- Set `address = ""` under `[location]`.

---

### Task 8: Verification, Documentation, and Git Push

**Step 1: Run complete test suites**
- `python3 -m unittest discover -s tests -v`
- `python3 tests/check_palette_matrix.py`
- `python3 tests/test_palette_surfaces.py`

**Step 2: Run `install.sh` and verify live symlinks**
- `./install.sh`
- Verify symlinks in `~/.config` and `~/.local/bin`.

**Step 3: Verify Hyprland and Noctalia configuration**
- `hyprctl configerrors`
- `hyprctl reload`
- `noctalia msg config-reload`

**Step 4: Commit and Push to GitHub**
- `git status`, `git commit`, `git push origin main`.
