# Rice Stabilization Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Finalize reviewed dotfiles, add offline CI, and document verified upgrade/performance findings without changing the running desktop.

**Architecture:** One small standard-library validator is shared by local checks and GitHub Actions. Native upgrade research stays in scratch source/build directories; the current transaction owner, configuration and launcher remain authoritative.

**Tech Stack:** Git worktrees, Bash, Python unittest/ast/json/tomllib, GitHub Actions, native C++23/Meson Noctalia.

---

Use @test-driven-development, @verification-before-completion and sequential
spec-then-quality review. The named Antigravity entry workflow is absent in
this OpenCode checkout; use the loaded executing-plans and
single-flow-task-execution skills directly, without adding unrelated tooling.

## Task 1: Finalize the four reviewed files

**Files:** `config/fish/config.fish`, `root/mimeapps.list`,
`state/noctalia/settings.toml`, `config/micro/bindings.json`.

1. Save existing contents/diffs to `/tmp/opencode/rice-stabilization-20261111`.
2. Validate the unchanged worktree's Fish config with `fish --no-config -n config/fish/config.fish` and confirm CachyOS already adds `$HOME/.local/bin`.
3. Remove this duplicate block from main, leaving all other Fish code intact:

   ```fish
   # Added by jcode installer
   if not contains "/home/admin/.local/bin" $PATH
       set -gx PATH "/home/admin/.local/bin" $PATH
   end
   ```

4. Parse saved TOML/JSON and verify the TextEditor desktop entry exists and T3Code is unavailable. Preserve all runtime choices.
5. Run Fish syntax, `noctalia config validate` and `git diff --check`; review the exact staged diff, then commit only the reviewed preferences/state.
6. Rebase only this newly created planning branch onto the new main commit, retaining user branches unchanged.

## Task 2: Add reusable validation and CI

**Create:** `tests/test_validate.py`, `tests/validate.py`, `.github/workflows/validate.yml`.
**Update:** `docs/DEVELOPMENT.md`, `AGENTS.md`, `docs/plans/task.md`.

1. Write test-first checks for valid Bash/Python/TOML/JSON files, each invalid format, symlink exclusion and tracked-file enumeration.
2. Run `python3 -m unittest discover -s tests -p test_validate.py -v`; require failure because the validator is absent.
3. Implement `validate(paths)` with `ast.parse`, `tomllib.loads`, `json.loads`, and `subprocess.run(['bash', '-n', str(path)], check=True)`. Skip non-files and symlinks. CLI enumerates NUL-separated `git ls-files` relative to the repository root, reports failures with filenames and returns nonzero.
4. Run focused tests to green, then `python3 tests/validate.py`.
5. Extract the offline checks from `audit/safe-optimization` rather than merging its old desktop changes. Use Ubuntu 24.04 Python 3.12, pinned checkout v6 (`d23441a48e516b6c34aea4fa41551a30e30af803`), `contents: read`, `persist-credentials: false`, jq/Lua/Node packages, and isolated HOME plus a scratch no-op systemctl for installer tests.
6. Run hosted-like unittests with native tools absent; preserve/print skips rather than claiming the palette matrix ran. Validate the workflow independently, run the full host suite, review, update guidance and commit.

## Task 3: Assess Noctalia 5.4.1 in isolation

**Artifacts:** `/tmp/opencode/noctalia-5.4.1-20261111/`.
**Report:** `docs/rice/STABILIZATION_2026-11-11.md`.

1. Clone the exact upstream `v5.4.1` tag into scratch; read any applicable repository guidance and Meson setup.
2. Export the complete `v5.3.0..ade8aa6c` diff from the clean live source worktree as an artifact; run `git apply --check` against 5.4.1.
3. Configure/build pristine 5.4.1 with retained dependency include/pkg-config paths and conservative parallelism. Run its registered tests when build/dependencies permit. Log all failures; do not silently change the dependency set or install.
4. Record color-role and `matugen_palette` incompatibilities, dashboard/API overlap, build/test result and explicit no-switch recommendation. Pristine build success alone does not authorize deployment.

## Task 4: Record real process measurements

**Report:** `docs/rice/STABILIZATION_2026-11-11.md`.

Record the completed 16-snapshot, 16.96-second `/proc` sample: median PSS/RSS,
mean CPU with 100%=one core, process counts, permission limits, available RAM,
swap and pressure. No tab/process changes. Explain that this is uncontrolled
session sampling, not a causal benchmark or guaranteed savings.

## Task 5: Audit wallpaper/theme without speculative refactoring

**Read:** `config/hypr/scripts/generate-theme.py`,
`config/quickshell/wallpaper-switcher/`, `config/matugen/`, relevant tests.
**Report:** `docs/rice/STABILIZATION_2026-11-11.md`.

Review ownership, serialized writes, output backups, native asset selection,
cache identity and rollback/acknowledgment. Run `python3 -m unittest discover -s tests -q`
and `python3 tests/check_palette_matrix.py --no-desktop`. Fix only a reproduced
in-scope defect via red/green regression; otherwise record the no-change decision.

## Task 6: UI decision and final verification

**Update:** `docs/rice/STABILIZATION_2026-11-11.md`, `docs/plans/task.md`.

Document no demonstrated reason to redesign Home/carousel or remove WIP
branches. Leave GUI acceptance unclaimed. Run validator, full tests, palette
matrix, native config validation, `hyprctl configerrors`, `git diff --check`
and scoped final review. Commit the evidence, fast-forward main locally,
rerun final checks and report exact commits plus skips. Do not push, switch
the Noctalia launcher, delete worktrees/WIP, or install desktop components.
