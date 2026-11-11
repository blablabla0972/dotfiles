# Rice stabilization — approved design

Approved in-session on 2026-11-11: complete the checklist, keep the live desktop
unchanged, create local commits only. No push, WIP deletion or launcher switch.

## Approach

1. **Selected:** preserve reviewed application/runtime preferences, add small
   offline CI from `audit/safe-optimization`, and research Noctalia separately.
   Low live risk, with native/visual coverage limits explicitly reported.
2. Immediate 5.4.1 migration: rejected because the system binary ignores
   `theme.matugen_palette` and requires color-role migration.
3. Report only: safe but does not deliver Git hygiene or CI.

## Git

Review exactly `config/fish/config.fish`, `root/mimeapps.list`,
`state/noctalia/settings.toml` and `config/micro/bindings.json`. Remove only the
verified duplicate jcode PATH block; keep TextEditor C++ associations, removal
of the unavailable T3Code handler, current Noctalia state and empty Micro
bindings. Do not treat disabled custom lockscreen widgets as a disabled locker.
Back up the four files before normalization and commit only reviewed paths.

## CI

One pinned Ubuntu job on push, pull request and manual dispatch; read-only
repository permissions and no persisted checkout credentials. Reuse the audit
workflow's tracked-file Bash/Python/TOML/JSON validation and isolated unittest
execution. Move syntax checking into one standard-library script, with tests
for valid files, invalid syntax and skipped symlinks. Install jq, Lua and Node
so the core helper/state-machine tests run. Native Noctalia/Matugen/ImageMagick
7/Qt/Quickshell checks may skip on the hosted runner; report those honestly,
and keep the full palette matrix as a separately verified host check. CI must
not install dotfiles or modify a live desktop.

## Noctalia

The live source is `ade8aa6c` based on local tag `v5.3.0`; old v5.2.1 root
documents are historical. Inspect the complete native diff, compare against
upstream v5.4.1, dry-check patch application and attempt a pristine isolated
build. Build and test logs stay outside live source/config. Never overwrite
the dirty `source/` checkout, install the candidate, stop the shell or change
the launcher. A successful pristine build is not patched feature/UI parity.

## Measurements, theme and UI

Record read-only process PSS/RSS and per-core CPU accounting from the actual
session, including interval and limitations. Keep Brave tabs, daemons and
effects unchanged. Audit transaction ownership, output coverage, cache,
acknowledgment and rollback using source plus regressions/palette matrix.
Refactor only for a reproduced defect or measured benefit. Keep dashboard,
carousel, top bar, Show Desktop, 144 Hz setup and WIP branches unless evidence
justifies a change. Uncoordinated GUI input is out of scope.

## Acceptance and recovery

Relevant focused tests, full unittests, syntax checks and palette matrix pass;
validate native config and compositor diagnostics without forced desktop
failures. Report CI/native/GUI skips and build or compatibility failures.
Merge the verified dotfiles branch locally to main; do not push. Preserve
generated files and runtime data. Noctalia rollback is unnecessary because
the launcher is not switched; Git changes remain individually revertible.
