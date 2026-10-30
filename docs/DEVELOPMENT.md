# Development guide

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
