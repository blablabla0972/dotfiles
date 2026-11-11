# Rice stabilization checkpoint — 2026-11-11

This checkpoint completes low-risk repository work and records measurements
and upgrade evidence without installing components, changing live symlinks,
stopping Noctalia, deleting WIP branches, or pushing commits.

## Git and CI

- The four pending paths were reviewed. The jcode Fish PATH block duplicated
  the CachyOS environment and was removed, returning `config/fish/config.fish`
  to its tracked contents. Commit `b2b70dc` preserves the current TextEditor
  C++ association, removal of the unavailable T3Code handler, Noctalia runtime
  state and Micro's empty binding map.
- All 15 documented managed live links were resolved after the old previews
  were removed; each points into the `main` checkout. README and agent guidance
  now record that checkpoint while still requiring resolution before edits.
- CI is intentionally offline and desktop-independent. It validates tracked
  Bash, Python, TOML and JSON, runs isolated unittests, and reports native
  palette skips. Validator regressions cover all supported formats, symlink
  exclusion, tracked-file enumeration and CLI status.
- Local evidence before the final merge: validator tests passed red-to-green
  (9 tests), the full host suite passed 219 tests, a hosted-runner simulation
  passed 219 tests with 30 native skips, and actionlint 1.7.12 accepted the
  workflow. Hosted CI is not a substitute for Matugen/Noctalia or visual tests.

## Noctalia 5.3.0 to 5.4.1 assessment

### Current and candidate revisions

- The running launcher remains `~/noctalia-dashboard-redesign/run-noctalia.sh`.
  It runs source commit `ade8aa6c17d72ee571d08d0f1b765e8894c07eb5`
  (`v5.3.0-14-gade8aa6c17d7`) with matching assets.
- CachyOS provides `/usr/bin/noctalia` 5.4.1-1.1. The pristine upstream tag
  tested here resolves to commit `815aebe1cfd79c9a18197441eea92f0b275035fc`.
- The old v5.2.1 root workspace documents are historical and must not be used
  as the upgrade base.
- The dirty `~/noctalia-dashboard-redesign/source` checkout was excluded from
  the comparison. Patch export came from the clean active source worktree
  `worktrees/bar-background-20261030` at `ade8aa6c`.

### Patch and API compatibility

The clean runtime branch differs from upstream v5.3.0 in 27 files (2,051
insertions and 500 deletions); `home_tab.cpp` alone adds 1,542 lines. Of those
27 files, 24 also changed upstream between v5.3.0 and v5.4.1. The exported
143,793-byte patch does not directly apply to v5.4.1. A three-way dry check
still reports content conflicts in:

- `src/shell/bar/bar.cpp`
- `src/shell/control_center/tabs/home_tab.cpp`
- `src/shell/control_center/tabs/media_tab.cpp`
- `src/time/time_service.cpp`

The non-conflicting hunks still require review against changed APIs; a clean
hunk is not feature parity. Scratch patch, overlap lists and apply logs are in
`/tmp/opencode/noctalia-5.4.1-20261111/artifacts/`.

Some local maintenance code should be removed rather than ported. In
particular, upstream commit `99f95cd6` implements clock wake scheduling across
34 files and supersedes the narrower local `ade8aa6c` clock optimization.
Conversely, upstream changed Home with avatar controls, compositor details,
media-visualizer settings and the container-role refactor, so the dashboard
conflict must be reconciled against new behavior rather than resolved by
choosing the old file wholesale.

The current theme pipeline also depends on two private v5.3 extensions:

1. `[theme].matugen_palette` overlays a generated custom palette while keeping
   `source = "wallpaper"`.
2. `color-palette-reload` reloads that file through IPC.

Neither exists in upstream 5.4.1. Upstream can load the same JSON schema with
`source = "custom"` and `custom_palette = "matugen"`, but that changes the
wallpaper-source and reload behavior used by the transaction script. The
system 5.4.1 validator confirms the gap: the current config is accepted with
16 warnings — 15 palette-role migrations plus unknown `matugen_palette`.
The renamed config roles are `surface_container` and `outline_variant`; theme
template token names are separate and retain their Material names.

There is a plausible lower-maintenance 5.4 port: use the supported custom
palette source, atomically replace `matugen.json`, then call the supported
`config-reload` IPC. In 5.4.1 `ThemeService::onConfigReload()` resolves the
palette unconditionally, while wallpaper-triggered palette generation only
runs for the wallpaper source. This could delete the private config field and
reload IPC instead of carrying them forward. It is not applied here because
the wallpaper hook, settings UI, transaction acknowledgment and rollback must
first pass the existing failure-path tests under that source change.
The system 5.4.1 binary accepted an isolated `source = "custom"` config with
`custom_palette = "matugen"` and resolved the existing generated palette to 74
tokens in each of dark and light modes. This proves schema compatibility, not
live reload or end-to-end transaction parity.

### Isolated build

The first debug attempt linked the shell binary but exhausted the 3.7 GiB
`/tmp` filesystem while linking 177 large test targets. This was an
environmental capacity failure, not a compiler error: the build occupied 3.5
GiB and only 81 MiB remained. Its log was retained and only that scratch build
directory was removed.

The retry used a release build under
`~/.cache/noctalia-5.4.1-20261111-build` with tests enabled. It built all
1,122 targets and produced `noctalia v5.4.1 (v5.4.1)`. GCC 16 emitted 20
warnings in upstream source/tests (conversion, maybe-uninitialized and one
string-overflow diagnostic), so this is not described as a warning-clean
build.

The first test invocation passed 173/177; all four failures reported that the
asset bundle was missing and then failed translated-label/glyph expectations.
Pointing `NOCTALIA_ASSETS_DIR` at the matching v5.4.1 `source/assets` made the
four focused reproductions pass, confirming the root cause. A fresh full run
then passed **177/177** tests. Source status and `git diff --check` were clean.
Logs are retained under the scratch artifact directory. No candidate was
launched or installed, and these pristine upstream results do not establish
dashboard patch or visual parity.

### Security and decision

Upstream 5.4.1 includes sender validation for logind/fprintd lock signals and
logind idle-inhibition state (commit `732e727c`), described upstream as fixes
for forged-signal authentication bypass and lock suppression. The local v5.3
patch does not touch those subsystems. A direct dry-run of that security patch
against the current runtime branch conflicts in `logind_service.cpp`, so even
an interim backport needs manual review and its own native tests.

**Decision:** do not switch the launcher to 5.4.1 now because patch, palette,
IPC and dashboard parity are not established. However, treat the native port
or reviewed security backport as P1 rather than indefinite P2 maintenance.
Before switching, manually port the four conflict areas, review all other
hunks, preserve or deliberately replace the Matugen transaction contract,
build the patched candidate, run native and transaction tests, then perform
coordinated dark/light, compact-layout and pointer acceptance with matching
assets and a rollback-ready launcher.

## Runtime resource sample

A read-only sample took 16 snapshots over 16.96 seconds in the real interactive
session. It summed proportional set size (PSS) across each process group to
reduce shared-page double counting and calculated CPU deltas from `/proc`; 100%
CPU means one logical core on this 12-thread machine.

| Process group | Maximum processes | Median PSS | Median RSS | Mean CPU |
|---|---:|---:|---:|---:|
| Brave | 25 | 2,170.7 MiB | 4,515.1 MiB | 89.40% |
| OpenCode | 2 | 483.7 MiB | 538.6 MiB | 4.70% |
| MemPalace MCP | 1 | 265.5 MiB | 273.9 MiB | 0.00% |
| Kitty | 2 | 107.6 MiB | 267.2 MiB | 0.77% |
| Chrome DevTools | 1 | 106.6 MiB | 138.9 MiB | 0.00% |
| Noctalia | 1 | 99.3 MiB | 192.4 MiB | 0.65% |
| Hyprland | 1 | 98.2 MiB | 179.0 MiB | 6.59% |

The machine had 7,746,068 KiB RAM total and 2,775,508 KiB available. Swap use
was about 947 MiB, but current pressure was negligible: memory and CPU
`avg10=0.00`; memory `avg60=0.06`, CPU `avg60=0.01`.

This is an observational sample, not an idle-vs-load experiment: tabs,
extensions, foreground pages and daemons were not changed, and CPU accounting
cannot include a process that exited between snapshots. It nevertheless puts
the next measurement in the right place. Brave was roughly 22 times Noctalia's
PSS and dominated sampled CPU; replacing or trimming the shell is not the
first RAM optimization. If RAM work continues, use Brave's task manager to
measure individual tabs/extensions under a controlled workload. Development
tools also account for substantial temporary memory, so measurements made
while OpenCode, MCP and DevTools are open should not be treated as the normal
desktop baseline. No process was killed or disabled from this sample.

## Wallpaper and theme audit

No defect or measured regression was reproduced, so this audit makes no source
refactor. The current separation is deliberate:

- `generate-theme.py` is the only writer/transaction owner. The carousel shell
  calls it through a thin JSON-acknowledgment wrapper; native wallpaper and
  mode hooks re-enter the same owner.
- One advisory lock serializes explicit applies and native hooks. Repeated
  native-selection checks stop stale events from committing. The request
  marker suppresses only a hook whose explicit transaction still owns the
  lock.
- Matugen is forbidden from setting wallpaper or running template hooks. Its
  three outputs are constrained by `MATUGEN_OUTPUTS`, written atomically, and
  keyed by mode, flags, binary identity plus content/metadata for the image,
  config and resolved template inputs. Corrupt, incomplete or raced cache
  records regenerate.
- Native template output hashes are rendered without hooks before commit, then
  compared after `templates-apply`. A host audit found all 9 configured native
  outputs among the 26 snapshot paths; no enabled output lacked rollback
  coverage.
- Snapshot restore preserves symlinks, targets, modes, toolkit preferences and
  generated files. Native writers are quiesced only for emergency rollback and
  never while the shell reports the session locked. Incomplete recovery keeps
  its snapshot and returns an unconfirmed/failed acknowledgment rather than a
  false success.
- The QML reducer accepts one exact schema/request/wallpaper/result pair and
  requires process exit status to agree. Hiding the picker does not kill an
  active transaction; a timeout remains unknown while the process completes,
  and only the latest explicit queued choice follows it.

There are superficial duplicates, but combining them would increase coupling:
the preview cache stores five read-only swatches from an immutable private
image copy, whereas the transaction cache stores complete rendered outputs;
the explicit-apply and native-hook flows share rendering steps but have
different selection ownership and rollback rules; and MD5 thumbnail keys are
implemented once in Bash and once in QML because they cross a process/language
boundary. Existing tests cover cache ABA replacement, alias retargeting,
rollback, stale events, malformed acknowledgments, competing requests and
thumbnail publication. Refactoring these paths without a reproduced fault
would trade tested duplication for a larger shared failure domain.

The audit does identify one version boundary: the current owner assumes the
private v5.3 Matugen field and reload IPC. The proposed 5.4 custom-palette port
must change those assertions and then rerun every transaction failure test;
that migration is not mixed into this stable branch.

## Dashboard and carousel decision

No dashboard or carousel source is changed. Noctalia consumed about 99 MiB PSS
in the observed session, the six-image carousel already has validated caching,
and no UI defect was reproduced. A speculative Home redesign or another
thumbnail optimization would not address the measured RAM leader and would
expand the already difficult 5.4 port. Existing top bar, Show Desktop, 144 Hz
monitor setup and WIP branches remain untouched. This is a no-change decision,
not visual acceptance; no uncoordinated pointer tests or screenshots were
performed.

## Verification summary

- Dotfiles validator: exit 0.
- Dotfiles unittests: 219 passed, no skips on the configured host.
- Isolated dark/light palette matrix: 24 cases, exit 0.
- GitHub workflow: actionlint 1.7.12 exit 0; hosted-tool simulation passed 219
  tests with 30 explicit native skips.
- Pristine Noctalia v5.4.1: 1,122 build targets completed; 177/177 Meson tests
  passed with matching assets.
- Live state remained on patched Noctalia 5.3.0; native config validation
  passed, Hyprland reported no config errors, eDP-1 remained 1920x1080 at
  144.005 Hz, and no user unit was failed.

## Follow-up after the Noctalia v5.4.1 upgrade

This follow-up supersedes the earlier live-version, security-backport, and
"Decision" conclusions above; they describe the state before the upgrade.

- The running process now uses
  `~/noctalia-dashboard-redesign/worktrees/noctalia-upgrade-current/build-v5.4.1-matugen/noctalia`;
  `noctalia --version` reports v5.4.1. The active checkout is commit
  `c92541014f46b06afec83a7b4a2505ff271d35c2`, descended from the peeled
  upstream v5.4.1 tag `815aebe1cfd79c9a18197441eea92f0b275035fc`.
- Upstream security commit
  `732e727c51e2d609263b413799577aa1a7e1de6e` is an ancestor of that tag. The
  rice delta does not change its sender-validation files in `src/auth/` or
  `src/dbus/`; its `panel_manager.cpp` changes cover control-center blur/rendering.
  The earlier recommendation to backport that commit is superseded by the v5.4.1
  base.
- The matching source snapshot is published at
  [`noctalia-dashboard-source:codex/noctalia-v5.4.1-current`](https://github.com/blablabla0972/noctalia-dashboard-source/tree/codex/noctalia-v5.4.1-current).
  The config role migration, settings schema 16, release build, and removal of
  the top-bar debug indicator are recorded in the updated README and RESTORE
  guide. The custom branch compiled and config validation passed; its own test
  suite was not run. The 177/177 result above applies to pristine upstream.

Actions runs `43049456203`, `43057316083`, and `43060755102` failed before
validation because the hosted runner could not resolve Ubuntu archive hosts
while installing Lua. The workflow now downloads pinned Lua 5.4.8
interpreter/compiler binaries from GitHub, verifies their SHA-256 digests, and
checks that `jq`, Node, and Lua are available before tests.

Run `43061621126` then executed all 219 unit tests; three end-to-end tests
failed because the isolated harness inherited the runner's `gsettings` binary
without its GNOME schema. The shared fixture now provides valid appearance
values through a no-side-effect `gsettings` stub.

The follow-up [Actions run `43062628925`](https://github.com/blablabla0972/dotfiles/actions/runs/43062628925)
passed validation and all executed unit tests: 219 ran and 30 were skipped.
The palette matrix remained skipped because its native-dependency gate was not
met, so this run does not verify desktop rendering at runtime.
