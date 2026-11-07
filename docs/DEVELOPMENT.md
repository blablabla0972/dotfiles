# Development guide

## Full-access follow-up (2026-11-07)

Full access resolved the earlier sandbox limits: Hyprland `reload config-only`
returns `ok` with no config errors; Noctalia config validates, mode is dark,
the eDP-1 output is 1920x1080 at 144.005 Hz, `swww-daemon.service` is active and
no user units are failed. Reapplying the current wallpaper returned JSON
`status=applied` for `dotfiles-verify-20261107`, without dirtying generated files.

Main now includes three previously preview-only source changes: Noctalia
`card_borders=false`, symlink-aware thumbnail enumeration, and the carousel's
initial selection, stable delegate geometry and selected border fixes.
The newer main palette hash fast path is retained. Focused tests cover linked
images and library roots; all 167 unittests pass with no skips, and all 24
palette cases pass against the running native shell's assets.
The candidate picker loads without QML runtime errors; the screenshot attempt
stalled in `grim` and was terminated, so visual acceptance is not inferred.
The portal app-ID registration warning remains; live links and user state are
unchanged, and only the temporary picker instance was stopped.

Native source `ade8aa6c` (VERSION 5.3.0) is published on
`noctalia-dashboard-source:dotfiles-runtime-20261107` and verified by ls-remote.
The native target rebuilt successfully; the launcher points to that build and
its matching assets. See [RESTORE.md](RESTORE.md) for prerequisites and the
portable launcher. Fresh OS installation and forced lock/suspend remain untested.
AGY Gemini 3.8 High completed the installer audit and implementation (job
`implement-mw6belih-f33e536d`). Backups now mirror HOME-relative destinations
under one per-run root, dry-runs report preview-only status, help distinguishes
script selectors, and explicit selectors take precedence over `--all` in both
behavior and reporting. Host review additionally fixed quoted HOME-prefix
matching, with an observed failing regression for spaces and literal brackets.
Rollback coverage unlinks installed destinations before restoring backups and
checks that repository sources remain unchanged; config, state and bin paths
are covered. Historical backup directories are preserved. The integrated suite
passes 171 tests with no skips and all 24 palette cases; shell syntax, selected
dry-run and diff checks pass. Backup layout and safe recovery are in RESTORE.md.

## Verification checkpoint (2026-11-07)

Rechecking `a86a7fd` found three E2E failures: native template staging treated
`pgrep` exit 1 (no running shell) as fatal, and E2E asset discovery used host
processes. The fix falls back to installed assets only for exit 1, preserves
other lookup errors, and gives E2E tests a scratch asset catalog. The palette
matrix command adapter now preserves subprocess error causes as production does.
Regression tests were observed failing before the fix and passing afterward.
All 166 unittests and 24 dark/light palette cases pass, with no unittest skips;
shell syntax, selected Hyprland installer dry-run and diff checks pass.
Noctalia config validates; compositor IPC is unavailable in this sandbox, so no
live reload, wallpaper transition, lock/suspend or visual acceptance is claimed.
Existing main and preview symlinks, generated files and unrelated Micro/MIME
edits are preserved. README documents the patched native Noctalia prerequisite
and its current source publication gap. AGY cannot start here (localhost socket
denied); GPT-6.1 Sol agents handled independent review and the E2E fixture.

## Audit verification checkpoint (2026-11-04)

All audit source fixes are implemented and applied to the running desktop; scope and evidence are in [AUDIT_FIXES_2026-11-04.md](rice/AUDIT_FIXES_2026-11-04.md). The reviewed changes are based on `70df281`; the user requested publication to `origin/main` on 2026-11-04. Unrelated Micro edits and local Graphify data are preserved; nine generated Graphify files are untracked/ignored, retained on disk.

Live testing corrected the initial hypridle proposal: Noctalia already owns `org.freedesktop.ScreenSaver`, handles logind locking and respects D-Bus/media, systemd and Wayland inhibitors. A second idle daemon conflicts and cannot inherit Noctalia's D-Bus inhibitors. Noctalia now owns dim=180 / lock=300 / screen-off=360 / lock-and-suspend=1800 seconds, with immediate actions, brightness restore and unchanged locked deadlines. Hypridle is inactive/disabled. Super+L calls native Noctalia locking; `hooks.started` preserves startup-lock intent after IPC is ready, including shell restarts, while config reload does not lock. Both locker layout/config files are preserved. A controlled idle181/reset0 test changed brightness 76800→19200→76800; logind reports `CanSuspend=yes`. Lock/suspend themselves were not forced during the user's session.

The three utility app IDs were tested in temporary native Wayland windows: Dolphin, Ark and pavucontrol all floated. Hyprland reload has no config errors; live blur passes=1 and monitor `eDP-1` is 144.005 Hz, giving transition FPS 144. Live carousel mapped in 0.445 s, displayed the ribbon/thumbnails correctly and had no runtime errors; the test instance was closed afterward. Its cold/cached producer, deferred fallback and mouse handling also passed isolated native tests. Cached-image availability benchmark: first notification 0.149 s, total 5.503 s for 40 synthetic 3840×2160 JPEGs, warm median 0.064 s; these are not GUI frame rates.

GPU check: repeatedly opened/closed native Control Center at 144 Hz, alternating blur passes 2/1, with two warmups then three trials per setting. Median Hyprland render-engine busy ratio was 24.208% at 2 passes and 22.508% at 1 (1.700 percentage points, about7.0% relative reduction). Measurements use deduplicated DRM client counters per the [kernel accounting specification](https://docs.kernel.org/gpu/drm-usage-stats.html); this short desktop workload is not a general FPS claim. The final setting is restored to 1.

The swww service is active; an actual transient systemd unit using the configured `ExecSearchPath` resolved the local daemon and ran `awww-daemon 0.12.1 --version` successfully. Missing Hermes is skipped with `ConditionResult=no`, inactive and zero restarts. No user units are failed. `systemd-analyze verify` still warns when its executable check ignores the optional missing Hermes binary and the bare swww lookup; runtime lookup/skip checks are the authoritative evidence, not a claimed clean verifier pass. Both GTK4 normal/dark CSS import chains parse, Brave's forced-dark startup flag is removed, and its existing browser process was not restarted.

Final automated checks: 164 unittests passed, 24 palette cases passed, shell/Lua/native config and diff checks passed. The matrix fixture now supplies the empty companion imported by newer native GTK templates; this failure reproduced on the original checkout and the fix affects scratch only. `qmllint` retains eight existing dynamic PathAttribute member warnings (main baseline 30, active carousel baseline 47), with no new diagnostics. Independent Standards/Spec reviews confirmed their findings were resolved, including the final native idle/locker integration.

The isolated candidate is `.worktrees/audit-confirmed-fixes`. Active Quickshell is `.worktrees/rice-audit-agy-20261030` (existing selection, linked-library and styling changes preserved); active Noctalia is `.worktrees/perf-panel-20261029` (`card_borders=false` and runtime palette/user tests preserved). Both previews received only the relevant fixes. Backups: `/tmp/dotfiles-carousel-preview-before/` and `/tmp/dotfiles-noctalia-preview-before/config.toml`. Generated theme outputs and acknowledgment/rollback ownership remain unchanged. To roll back, selectively restore reviewed main edits and these preview backups, then reload; keep one idle/locker owner.

The initial sandbox/approval rejection was superseded by actual Full Access in the subsequent turn. All required live checks above were then run through the authorized terminal; no unresolved permission blocker remains.

## Latest verification checkpoint (2026-10-29)

Accent preview: the user selected stronger accents/depth. Worktree `.worktrees/accent-depth` (`feat/accent-depth`) changes only the carousel selected border (3 → 4 px) and adds an 8% primary-color overlay, with no new effect passes. `install.sh --no-state quickshell` installed this worktree for the next carousel launch; other components remain on main. To revert the preview, run `./install.sh --no-state quickshell` from the main checkout. Native qmllint reports 30 existing diagnostics versus 31 in the candidate (one additional outer-ID unqualified-access warning); this is not a clean lint pass. Live visual acceptance remains pending because Hyprland IPC is unavailable. The candidate is not merged or pushed.

On the working tree based on `8231b52`, `python3 -m unittest discover -s tests -q` passed all 121 tests (no skips reported), and `python3 tests/check_palette_matrix.py --no-desktop` exited successfully. These are offline checks, not visual or performance acceptance. `hyprctl configerrors` could not connect (`Couldn't set socket timeout (2)`); live compositor validation remains pending. Existing documentation and Noctalia runtime changes were preserved. Next: inspect the current theme/carousel implementation through the existing CodeGraph index, then measure a concrete bottleneck before changing behavior.

This repository versions a CachyOS/Hyprland desktop setup; it is primarily configuration and shell/Python/JavaScript scripts rather than a packaged application. Start with the repository map and live-file safety rules in [`../AGENTS.md`](../AGENTS.md). User-facing machine and install notes are in [`../README.md`](../README.md).

## Setup and install

### Thumbnail performance baseline (2026-10-29)

Measured the unmodified `config/quickshell/wallpaper-switcher/generate-thumbs.sh` in a temporary HOME/cache with 40 synthetic 3840×2160 JPEG gradient images: first generation took 5.063 s; the median of five subsequent cached runs was 0.066 s. All 40 thumbnails were produced. Temporary data was removed; the desktop and actual wallpaper cache were not touched. This measures script elapsed time, not carousel frame rate or real photographic image decoding. Existing disk caching already avoids most repeat work, so replacing it is not justified by this measurement. Next investigate first-open thumbnail scheduling and image loading in the QML entry point; CodeGraph did not resolve `shell.qml`, so its results cannot establish QML behavior.

Clone the repository, enter its root, and inspect the installer's planned links before installing:

```bash
# Replace OWNER with this repository's GitHub account or organization.
git clone https://github.com/OWNER/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run
./install.sh --no-state
```

Replace `OWNER` with the repository's GitHub owner. The default installer links the live desktop subset and backs up replaced targets in `~/.config/backups/`. `--all` includes snapshot/systemd configuration; a selected `noctalia` target or `--all` may link `state/noctalia/settings.toml`. Use `--no-state` when the machine's saved Noctalia session should be retained. Installation changes symlinks, so preview its output and select components deliberately.

The repository does not pin or bootstrap operating-system packages. Tests use Python's standard `unittest`; some integration tests detect external programs such as Matugen, ImageMagick, Node.js, Lua, Quickshell, or Noctalia and skip when unavailable. Check test output for skips on a new machine.

## Tests and checks

Run the full suite from the repository root:

```bash
python3 -m unittest discover -s tests -q
```

Run the isolated palette/template matrix:

```bash
python3 tests/check_palette_matrix.py --no-desktop
```

The tests cover installer safety, theme synchronization and rollback, token derivation, cached Matugen rendering, wallpaper-picker state and helpers, plus palette contrast. The matrix renders 12 palette fixtures in dark and light modes into temporary directories and checks native templates without changing the desktop. Run one module while iterating with, for example, `python3 -m unittest discover -s tests -p 'test_carousel.py' -q`.

For changed shell scripts, check shell syntax:

```bash
bash -n install.sh wt-prep.sh \
  config/quickshell/wallpaper-switcher/apply-wallpaper.sh \
  config/quickshell/wallpaper-switcher/generate-thumbs.sh
```

Before handing off a change, review `git diff --check`, `git diff`, and `git status --short`. No build, lint, format, typecheck, or CI command is configured in the repository. Do not report those checks as passing unless a project tool is added and actually run.

On the configured desktop session, reload only the component you changed. Existing commands are `hyprctl reload config-only`, `noctalia msg config-reload`, and `noctalia msg color-palette-reload`; check compositor diagnostics with `hyprctl configerrors` and validate Noctalia configuration with `noctalia config validate`. Run relevant commands from the live session. A successful offline suite does not establish that a live theme, focus behavior, display scale, or lock screen was visually tested.

## Project conventions and file ownership

- `config/` contents usually become `~/.config/<name>` symlinks; `root/` contains individual config files, `state/` contains app state, and `bin/` contains user utilities. Not every snapshot is installed by default; `install.sh` is authoritative for selector behavior.
- The Hyprland configuration uses Lua modules under `config/hypr/config/`. Keep bindings and desktop behavior in their owning module and preserve existing Noctalia integration.
- `config/hypr/scripts/generate-theme.py` owns Matugen output and wallpaper transactions. Update source templates/configuration rather than editing generated outputs by hand. The adaptive token source is `config/rice/theme/derive_tokens.py`.
- The wallpaper picker lives in `config/quickshell/wallpaper-switcher/`; its QML delegates apply/preview state to `ApplyState.js` and its helper scripts. Keep the existing single transaction owner, JSON acknowledgment, cache keys, and rollback behavior intact.
- Generated/host-specific files include the Matugen outputs `config/hypr/colors.conf`, `config/hypr/noctalia.lua`, `config/noctalia/palettes/matugen.json`, and `config/micro/colorschemes/adaptive.micro`; `config/hypr/current_wallpaper` and `config/hypr/gpu/` are machine-specific; `state/noctalia/settings.toml` is runtime-written. Theme caches are disposable under `XDG_CACHE_HOME`; transaction/adaptive state and snapshots are under `XDG_STATE_HOME` (default `~/.local/state`). Check `.gitignore` and `git status` for the current checkout rather than assuming every runtime file is ignored.
- Preserve user changes, ignored machine data, and unrelated untracked files. Do not use broad staging (`git add -A`) for a desktop snapshot; stage only reviewed task files.
- Commit subjects in recent history use short prefixes such as `fix:`, `perf:`, and `docs:`; keep commits focused if a commit is requested.

## Worktree, preview, and completion

Use `git worktree` for isolated desktop/config changes. `wt-prep.sh` copies host-specific wallpaper/GPU inputs into a prepared worktree and removes its existing destinations first; use it only on a new worktree. Review `./install.sh --dry-run --no-state <changed-components>` before preview, then install only those components with `--no-state`. The installer records backups. Do not apply snapshot/systemd components unless requested.

Before declaring work done:

1. Confirm the diff is limited to requested source and documentation; do not include generated outputs or unrelated machine files.
2. Run the relevant focused tests and the full suite when behavior changes; run the palette matrix when touching colors/templates. Report skips and external tools that were unavailable.
3. For live configuration changes, validate the affected native configuration and compositor errors when available. Distinguish that result from screenshot, monitor, input, lock, or performance checks that were not performed.
4. State changed files, verification results, rollback/ownership details, and unresolved questions. Do not claim full visual or hardware acceptance from isolated tests.
