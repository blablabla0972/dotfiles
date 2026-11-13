# Dynamic Island reference research — 2026-11-13

Status: original research snapshot, now followed by an uncommitted implementation
in the control-center-motion worktree. The original proposals and test counts
below describe the research stage. No reference shell was installed or executed.
Existing control-center motion and Wi-Fi work is preserved.

## Implementation checkpoint — 2026-11-13

The in-place Island now coordinates a 760×440 Dashboard morph with fixed-size
clipped content, media hover dwell/grace, pinning and paused-player access.
Transient requests are dropped while a modal panel opens or closes; notification
and OSD lifetimes reset to 4000 ms and 2200 ms respectively. Its input mask
releases the full-screen scrim as soon as the Dashboard begins closing.

Native Qt regression coverage includes reversible transitions, the real hover
and pin handlers, alert arbitration, timer expiry and modal input gating state.
At this initial checkpoint, 260 unit tests passed, the validator and
`git diff --check` were clean, and Quickshell IPC responded. Later verification
supersedes this snapshot; see the live acceptance section below. Objective
before/after frame-time/RAM improvements remain unmeasured.

## Reference snapshots

All four repositories were cloned under
`/tmp/opencode/island-references-1jz0r8q5`. Their HEADs were checked against the
fetch manifest and their working trees are clean. Links below use those exact
commits rather than moving branches.

| Repository | Commit | License file |
|---|---|---|
| [Tide-island](https://github.com/enhaoswen/Tide-island/tree/859842372b6fb138ac17c8d22ff3dd2809bb8181) | `859842372b6fb138ac17c8d22ff3dd2809bb8181` | GPL-3.0 text |
| [Ukishima](https://github.com/amanhex/Ukishima/tree/d04d8e1575bf0f7fc42922df7dca1ee9ac3a4027) | `d04d8e1575bf0f7fc42922df7dca1ee9ac3a4027` | MIT |
| [k4](https://github.com/k4ditano/k4/tree/5b1406c2267440c97c4c9986a9fa19c7424094c0) | `5b1406c2267440c97c4c9986a9fa19c7424094c0` | MIT |
| [impasto](https://github.com/andreumassanet/impasto/tree/76a1a4f84fea085905b9b0bdef6842fd8e3cd919) | `76a1a4f84fea085905b9b0bdef6842fd8e3cd919` | GPL-3.0 text |

The original third and fourth URLs were concatenated; they were treated as
separate `k4ditano/k4` and `andreumassanet/impasto` references. Tracking query
parameters were omitted. Tide's README redirects future work to another
repository; that repository was not substituted for the requested reference.
Borrow interaction principles, not source/assets. Any later source copying
requires a separate license/attribution check.

## What is worth borrowing

### Tide-island: coordinated reveal and surface-sized input

- [DynamicIslandWindow.qml:147–205](https://github.com/enhaoswen/Tide-island/blob/859842372b6fb138ac17c8d22ff3dd2809bb8181/DynamicIslandWindow.qml#L147-L205)
  composes input regions from visible surfaces and a separately bounded gesture
  strip. Expanded content does not silently enlarge the gesture strip.
- [OsdLayer.qml:19–47](https://github.com/enhaoswen/Tide-island/blob/859842372b6fb138ac17c8d22ff3dd2809bb8181/qml/island/OsdLayer.qml#L19-L47)
  connects opacity and slide offset to reveal progress, with different entry
  and exit durations.

Apply the principles to our existing mask and OSD; do not import the custom
`IslandBackend`, control center, file shelf, lock screen, or their services.

### Ukishima: content should arrive with the geometry

- [Pill.qml:933–1037](https://github.com/amanhex/Ukishima/blob/d04d8e1575bf0f7fc42922df7dca1ee9ac3a4027/Pill.qml#L933-L1037)
  separates target size from animated size and computes `morphCloseness` from
  their difference. Content visibility follows actual geometry, not an
  unrelated timer. Short rest/hover moves have a different timing budget from
  large panel moves.
- [Pill.qml:104–181](https://github.com/amanhex/Ukishima/blob/d04d8e1575bf0f7fc42922df7dca1ee9ac3a4027/Pill.qml#L104-L181)
  distinguishes pointer hover, explicit pinning, and expansion latches.
- Surface loaders and closed-surface retention are useful for a large shell,
  but are unnecessary machinery for our one small media card.

Do not copy its entire surface catalogue, weather work, shadow effects, or
memory-retention system. Reference comments about performance are not
measurements of this desktop.

### k4: user intent outranks stale transient feedback

- [shell.qml:31–108](https://github.com/k4ditano/k4/blob/5b1406c2267440c97c4c9986a9fa19c7424094c0/shell.qml#L31-L108)
  selects the highest-priority enabled active plugin. When a non-transient view
  takes over, the host closes other active transients centrally, preventing
  them from resurfacing after the requested view closes.
- [shell.qml:1180–1235](https://github.com/k4ditano/k4/blob/5b1406c2267440c97c4c9986a9fa19c7424094c0/shell.qml#L1180-L1235)
  distinguishes preserving an existing hovered view immediately from dwelling
  at an otherwise empty hidden edge.
- [shell.qml:1280–1338](https://github.com/k4ditano/k4/blob/5b1406c2267440c97c4c9986a9fa19c7424094c0/shell.qml#L1280-L1338)
  lays out content at its target size inside a clipped animated container and
  activates only the selected view loader.

Use a small explicit arbitration rule and fixed-size content in our existing
components, not a plugin manager or a general-purpose extension API.

### impasto: small state resolver, hover intent, landing guard

- [IslandState.qml:14–26,60–72](https://github.com/andreumassanet/impasto/blob/76a1a4f84fea085905b9b0bdef6842fd8e3cd919/home/.config/quickshell/bar/island/IslandState.qml#L14-L72)
  separates arbitration from rendering: user panel, notification, OSD, hover
  summary, rest.
- [IslandState.qml:93–121](https://github.com/andreumassanet/impasto/blob/76a1a4f84fea085905b9b0bdef6842fd8e3cd919/home/.config/quickshell/bar/island/IslandState.qml#L93-L121)
  drops OSD while a user panel is open rather than replaying stale feedback.
- [DynamicIsland.qml:242–348](https://github.com/andreumassanet/impasto/blob/76a1a4f84fea085905b9b0bdef6842fd8e3cd919/home/.config/quickshell/bar/widgets/DynamicIsland.qml#L242-L348)
  uses hover dwell, exit grace, re-entry cancellation and a landing guard so
  hover cannot hijack a closing panel halfway through its morph.
- [DynamicIsland.qml:396–411](https://github.com/andreumassanet/impasto/blob/76a1a4f84fea085905b9b0bdef6842fd8e3cd919/home/.config/quickshell/bar/widgets/DynamicIsland.qml#L396-L411)
  avoids independently animating geometry derived from another animated value.

Do not bring over its notes, games, extra services, module framework, or
active-monitor routing without a separate requirement.

## Existing implementation: keep vs improve

The shell already has media transport/seek/artwork, an inline media pill,
OSD/notification rendering, shared notch geometry, outside-click and Escape
dismissal, an input mask, native MPRIS, and multi-monitor IPC. These are not
missing features to reimplement.

| Finding | Evidence | Scope/qualification |
|---|---|---|
| Media/hover arguments do not affect overlay state | `island/IslandState.js:22–25`; Node execution returned `idle` for playing media both with and without hover | The inline bar already displays playing media. Blindly enabling an always-on overlay would duplicate it. |
| Exit animation cannot finish while the window is hidden immediately | `island/Island.qml:17`, `95–102`; expiry selects idle, and idle dimensions are zero | Static lifecycle finding; new native regression is still required. |
| Priority declaration is unused; later alerts overwrite the single alert | `IslandState.js:11–17`; `Island.qml:75–93` | Explicit pinning already wins in the resolver. Missing protection concerns incoming alert replacement and stale feedback, not pin priority itself. |
| OSD can inherit the notification's longer timeout | `Island.qml:91` sets 4000 ms; `triggerOsd()` restarts without restoring 2200 ms | Static finding; test notification → OSD before changing it. |
| Inline and overlay have separate geometry and lifecycles | `bar/Bar.qml:103–147`; `Island.qml:136–158`; `shell.qml:24–34,165,192–194` | Current handoff is a fade between two surfaces, not a single-body morph. |
| Pausing makes the bar show Control Center instead of the player | `Bar.qml:141,156,202` | Existing semantics, not a crash; retaining access to a paused player is a proposed behavior change. |
| Bound waveform delegate uses an undeclared `index` | `Island.qml:410–416` | An earlier live run logged `ReferenceError: index is not defined`; no new live run was performed during this research stage. |

Paths in this section are relative to `config/quickshell/rice-shell/`.

## Three approaches

1. **Harden and polish the current Island — recommended.** Keep the current bar,
   media-card layout, palette, IPC and two-surface architecture. Fix expiry,
   alert arbitration and the waveform binding; add reversible reveal with
   fixed-size content and a coordinated bar handoff. Add a media-only hover
   preview with dwell/grace, and retain paused-player access. This is a bounded
   behavior/motion improvement, not a claim of perfect single-body morphing.
2. **Unify the center pill and overlay into one visual owner.** Better spatial
   continuity for every state, but a wider change to bar ownership, sizing,
   input, multi-monitor instances and interaction tests. Leave the dashboard
   separate; it does not need to become another Island panel.
3. **Port a reference shell/plugin framework.** Largest compatibility and
   maintenance cost, unnecessary services and possible license obligations.
   Not justified by the requested Island improvement.

## Proposed acceptance criteria for approach 1

These require user confirmation before implementation:

- Preserve dark default, semantic tokens, bar ends, dashboard's 760×440 layout,
  sidecars, theme transaction ownership and existing IPC names.
- Keep idle click/right-click behavior. With a player available, including
  paused playback, preserve access to media controls.
- Media hover opens a non-modal preview after an initial proposed 150 ms dwell;
  leaving closes after 240 ms grace; re-entry cancels closing. Clicking pins;
  Escape/outside click releases pinning. Hover must not immediately reopen a
  just-dismissed card until the pointer leaves.
- User-opened media wins over automatic overlays. Notification feedback wins
  over OSD feedback. Drop transient display requests that would replay stale
  content after explicit dismissal; do not delete notification history.
- Restore 2200 ms OSD and 4000 ms notification lifetimes for each new request.
- Keep the media card's existing final size. Content stays at target dimensions
  behind clipping; opening/closing can reverse safely; visual lifetime and
  input lifetime are separate so closing does not leave a fullscreen click
  blocker. Coordinate inline-pill visibility with completion of overlay exit.
- Stop visualizer work when not presented; fix its bound delegate index.
- Add state/timer and native Qt motion/input regressions, then run the full
  suite and targeted live checks/screenshots. Do not add production test hooks,
  dependencies, daemons, a plugin API, or generated-theme edits.

## Documentation and verification limits

Context7 resolved Quickshell and returned the official
[QsWindow mask](https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/) and
[Region](https://quickshell.org/docs/v0.3.1/types/Quickshell/Region/) documentation.
`mask: null` means the default whole-window input; a non-null empty `Region`
is different. Region item geometry overrides explicit x/y/width/height.
These retrieved docs target 0.3.1; the previously checked installed runtime is
0.3.2, so native input tests remain necessary.

Fresh research-stage checks:

- `python3 -m unittest discover -s tests -q`: **246 tests, OK, no skips**, 39.709 s.
- `python3 tests/validate.py`: exit 0.
- `git diff --check`: exit 0 before adding this report; rerun after the docs edit.
- Node execution of the current state resolver confirmed the cases above.
- All four reference HEADs match the manifest; all four working trees are clean.
- `readlink -f ~/.config/quickshell` resolves to this isolated worktree's
  `config/quickshell`; no link, runtime state or generated output was changed.

No new Island runtime regression, screenshot acceptance, FPS/RAM measurement,
reference-shell execution, merge, push or shutdown is claimed. Existing tests
passing does not verify the proposed Island behavior. User requested shutdown
after the task finishes; approval and implementation are still pending, so no
power action has been taken.

## Implementation follow-up — 2026-11-13

The research-stage notes above describe the earlier baseline. Under the user's
subsequent instruction to proceed with rice improvements, the isolated worktree
now implements the bounded Island refinement: media hover dwell/grace, pin and
dismiss handling, alert priority and expiry, paused-player access, coordinated
bar/overlay motion, fixed-size content, stopped hidden visualizer work, and
focus-aware Escape handling. A moving `Region` input mask tracks the capsule's
visible body and uses the full scrim while a modal surface is open.

Fresh checks after these changes:

- Native regression red/green was observed for focused drawer Escape, for
  media hover after an alert expires under a stationary pointer, for an alert
  interrupting an already-open hover, and for a paused player with no title.
  **18 targeted motion tests** passed after the fixes, including the MPRIS
  elapsed-time refresh regression when expanded media is visible versus hidden.
- `python3 -m unittest discover -s tests -q`: **261 tests, OK**, 66.792 s
  (fresh run after the MPRIS timer and the final clock edit).
- `python3 tests/validate.py`, `git diff --check`: exit 0; a fresh
  `hyprctl configerrors` query retains a diagnostic from a previous unsuccessful
  `hl.dispatch("movecursor", "959 22")` experiment. This diagnostic was not
  observed as a new Quickshell configuration load failure.
- Island now clears hover dwell/grace and the active preview on incoming alert,
  uses `Media.hasPlayer` to preserve untitled paused-player controls, and runs
  the waveform timer at 110 ms with a 90 ms bar transition so frames do not
  overlap continuously. These behaviors are verified by native Qt state tests
  or source inspection, not a compositor FPS benchmark.
- The Bar clock now uses Quickshell `SystemClock.Minutes` instead of a 1-second
  custom timer for an `hh:mm` display. Context7's Quickshell 0.3.1 API documents
  minute precision; the full-suite result above covers this clock edit.
- Expanded media now emits `MprisPlayer.positionChanged()` once per second
  while visible, playing and position-supported so track elapsed time and
  progress update; its timer stops after dismissal. Native Qt regression proves
  the visible and hidden tick behavior. Live playback was not reverified.
- The running Quickshell instance loaded the edited configuration at 10:44:30.
  Wayland screenshots checked Dashboard 760×440, Wi-Fi drawer position, and
  complete disappearance after dismissal. The existing `IpcHandler` property
  warnings persist; no new load error appeared in the inspected log tail.
- A single idle-process snapshot measured 1.75% of one CPU core over four
  seconds and 57,728 KiB RSS (PID 357213). This is not a before/after
  benchmark and does not prove an efficiency gain.

**Remaining acceptance limits:** The native Qt test harness substitutes the
real LayerShell window and removes `Region` to test isolated behavior. A
temporary Linux input device subsequently enabled live pointer movement and
clicks despite the unavailable Hyprland `movecursor` dispatcher. On the real
1920×1080 Wayland desktop, a click at approximately (959,22) opened the
Dashboard; clicking outside at (1695,299) dismissed it. Another click at
(890,4), beyond the visible capsule, left it closed. The observed screenshots
are `/tmp/rice-input-open-small-20261113.png`,
`/tmp/rice-input-outside-small-20261113.png`, and
`/tmp/rice-input-margin-small-20261113.png`. These observations support basic
click and outside-dismiss behavior, but do not establish pixel-perfect rounded
corner click-through to the underlying application or focused-keyboard Escape
on the compositor. Only one connected monitor is present, so multi-monitor
interaction also remains unverified. The pointer was returned to its prior
desktop area and the Dashboard was dismissed through IPC. No merge, commit,
push, restart or power action was performed.

## Follow-up verification on the live Wayland desktop — 2026-11-13

- Source-informed enhancements now include a Tide-style layer that grows
  ahead of the Island morph and shrinks after a one-second grace period;
  viewport-aware side drawer geometry, lazy Wi-Fi/Bluetooth bodies and stable
  clipped content inspired by k4; and subtle bar/tab color transitions.
  These are local adaptations, not copied reference source or assets.
- Live Quickshell PID `357213` on `eDP-1` (1920×1080) reported two idle
  40px layers. A public `islandOsd` IPC call raised one to 46px at 0.18s
  and 0.9s, then returned both to 40px by 3.7s. The Dashboard grew one
  layer to 1080px, retained 448px during the close morph, and settled
  back to 40px after the delayed shrink.
- A transient `/dev/uinput` keyboard and mouse were registered with Hyprland;
  clicking the opened Dashboard's header gave it keyboard focus, after which
  Escape closed it and both layers settled at 40px. Opening solely through
  IPC without a pointer focus event did not give the panel keyboard focus;
  the usual click-open flow did. Devices were destroyed and the pointer was
  returned to its original coordinates.
- Public `toggleSideDrawer` IPC switched between visible Wi-Fi and Bluetooth
  drawers while preserving the fixed 760×440 dashboard. Live captures:
  `/tmp/rice-live-dashboard-20261113.png`,
  `/tmp/rice-live-wifi-20261113.png`,
  `/tmp/rice-live-bluetooth-20261113.png`. No Wi-Fi or Bluetooth connection,
  configuration or system power action was performed.
- Latest full host run: **267 tests, OK**, no reported skips; `python3
  tests/validate.py` and `git diff --check` both exit 0. Existing WIP and
  the live configuration link remain in the isolated worktree; no commit,
  push, restart or shutdown was performed.

Remaining hardware limits: only one monitor is connected. Multi-monitor
placement and pixel-level rounded-corner input pass-through to a background
application have not been independently established. The `hyprctl
configerrors` diagnostic described above arose from an earlier failed
cursor-dispatch experiment, not this test run.

## Deferred drawer initialization cleanup — 2026-11-13

Removed two permanently hidden `WifiDrawer`/`BluetoothDrawer` instances from
`QuickSettings.qml`, together with stale open-state toggles. The visible
buttons still emit `requestSideDrawer`, and `Dashboard.qml` remains the single
owner of the lazy-loaded side drawer bodies. This avoids initializing the
network and Bluetooth drawer component trees while they are closed.

Fresh focused regression runs: Dashboard control-center **13/13** and native
motion **20/20**. Full host suite **267/267** OK in 66.065s;
`python3 tests/validate.py` and `git diff --check` exit 0. No desktop
restart was performed; the source change has not been claimed as independently
reloaded in the running Quickshell instance.

## Home content lazy loading and independent audit — 2026-11-13

`Dashboard.qml` now gives Home the same conditional `Loader` lifecycle as the
System and Config tabs. Its content is constructed only while the Dashboard
is visible and Home is selected, remains available through the close animation,
and is released after close. The native Qt harness checks the actual loader
state during opening, closing, closing completion and reopening. Its real
settings UI and drawer request signal stay unchanged.

Fresh final run after this change: **268/268** host tests OK in 63.656s,
including **21** native motion tests and **13** control-center checks;
`python3 tests/validate.py` and `git diff --check` exit 0.

A separate read-only 45.3s observation of the *currently running pre-reload*
Quickshell PID 357213 sampled idle CPU/RSS 90 times at 0.5s intervals:
CPU mean **1.13%** of one core (p95 4.0%); RSS median **36.8 MiB**
(range 36.6–39.6 MiB, later snapshot 47.8 MiB); 40px/40px layers.
This is a reproducible idle baseline, **not** a before/after speedup claim;
neither active frame time nor unloaded/reloaded memory comparison was measured.
At 144 Hz, the 6.94ms frame budget is a target, not observed render latency.
An independent visual audit also noted that a 300px side drawer may overlap
the fixed-size card on narrower screens; this is currently the documented
small-screen fallback and was not altered without corresponding acceptance QA.
The live desktop was left running, and no commit, push or power action occurred.

## System telemetry process cadence — 2026-11-13

An independent read-only sample found that the System page starts `telemetry.py`
every 2 seconds when visible; eight isolated executions took a median of
263 ms wall time and 62.5 ms CPU time. `System.qml` now samples every 5 seconds,
with its visible freshness label updated to match. Immediate refresh when the
tab appears is retained. This schedules 60% fewer subprocess starts while the
System tab stays open; it is not a measured reduction in live desktop CPU usage.
The running Quickshell process has not been reloaded for this change.

## System telemetry persistent sampler — 2026-11-13

`System.qml` now starts one `telemetry.py --watch` process only while the
System tab is visible. A line-delimited `SplitParser` updates the existing
sample/history UI every five seconds, and hiding the tab terminates the
process. Initial data arrives after the same 200ms CPU measurement window;
the original single-snapshot CLI is preserved. This avoids restarting the
Python interpreter on every sample, per Quickshell 0.3.1 `Process` and
`SplitParser` documentation.

In one isolated five-snapshot comparison, fresh Python processes consumed
**313.8ms** total CPU versus **63.7ms** for one reused process. These figures
measure only sampler CPU under a short test interval, not a live desktop CPU
improvement; a persistent interpreter also remains resident while System is
open. The targeted telemetry tests, validator and diff check passed; live
Quickshell was not reloaded for this change.

An additional native Quickshell regression loads `System.qml` inside an
offscreen `FloatingWindow`, receives a live snapshot, hides the System view,
then reopens it and checks that sampling resumes. The targeted Dashboard suite
passed 15/15. Using a real window as the host matters: a parentless `Item`
directly beneath `ShellRoot` cannot be reliably hidden and shown again in
this test environment. With tray and notification lifecycle regressions added,
the full host suite passed 275/275; the desktop process remained running.

A further source-only safeguard marks System telemetry stale after 12 seconds
without a new valid snapshot, even when its Python process has not exited.
An isolated native Quickshell harness with a deliberately stalled telemetry
producer confirmed the stale indicator, and the focused Dashboard tests passed
16/16. A screenshot review of the previous live desktop showed `Bluetooth`
clipped in its narrow Quick Controls tile, so the tile now uses `BT` at widths
below 117px. Neither change has been reloaded into the live shell.

## Notification expiry and closing input regression — 2026-11-13

The notification lifecycle uses the D-Bus `expireTimeout` value in raw
milliseconds on the installed Quickshell 0.3.2, with a five-second fallback
for -1 and no automatic expiry for 0. Each received notification is tracked,
its expiry timer is disposed on `closed`, and `keepOnReload: true` retains
active notifications across a Quickshell reload. Old-generation notifications
are re-emitted internally but filtered from the island popup via
`lastGeneration`; this avoids closing active client notifications on reload.
An isolated real `NotificationServer` test over a private `dbus-run-session`
verifies 1-second expiry, zero-timeout persistence, no duplicate popup and no
`NotificationClosed` on reload. The integration fixture also imports the
production `Loader` and `riceIpc.islandNotification` dispatch from `shell.qml`,
using a mock Island to verify the entire signal path without touching the
live desktop. Focused notification tests passed 5/5.

The Dashboard's pill `MouseArea` is now enabled only while the Dashboard is
expanded. When the close morph begins, pointer input reaches the underlying
Island again instead of being absorbed by the fading Dashboard. Native
offscreen mask/input regressions passed 3/3. The complete host suite passed
280/280, `tests/validate.py` passed, and `git diff --check` passed. The live
Quickshell PID 357213 (0.3.2) remained running without reload, so the new
Bluetooth label, telemetry watchdog, notification path and close-state input
behavior still need live visual/interaction acceptance.

## Telemetry recovery and notification reload refinement — 2026-11-13

System telemetry now restarts its producer after a 12-second stall, even if
the process is emitting malformed JSON. Only valid RAM/disk/uptime snapshots
reset the watchdog; CPU-only missing values are accepted as partial snapshots.
Hiding System clears its CPU history, avoiding old graph data after reopening.
The `Last 2.5m` label matches the 30 samples at a five-second cadence. A
native offscreen regression exercises a corrupt stream and a real 1500ms
restart interval; the focused Dashboard suite passed 18/18. The full host
suite passed 282/282, `tests/validate.py` and `git diff --check` passed.

Notification reload preservation was verified against Quickshell's actual
offscreen D-Bus behavior. The manual `toggleNotifications` IPC deliberately
opens the last notification when invoked, including in DND, while automatic
delivery remains suppressed during DND. New shell source has not been loaded
into the live Wayland session; multi-monitor and input-mask visual acceptance
remain outstanding.

## Follow-up regression and interaction polish — 2026-11-13

The isolated D-Bus integration now exercises `expireTimeout: -1` using a real
notification sender, checks the five-second fallback, and observes a normal
`NotificationClosed` expiry (reason 1). The new regression prevents an
unbounded notification lifetime caused by treating negative timeouts as zero.

The Island now re-arms its media hover dwell when Dashboard finishes closing
under a stationary pointer, as long as no alert or modal is active. The tray
menu resets its scroll offset whenever its menu path changes, covering both
switching to a different tray item and entering a submenu. Native offscreen
regressions cover both behaviors. Media transport buttons also disable the
hand cursor when the MPRIS capability is unavailable and dim unavailable
previous/next controls; their existing tap guards remain in place.

Before the later parallel UX patches, the complete host suite passed
**283/283** in 92.201 seconds, `tests/validate.py` and `git diff --check`
passed; the focused Island suite then passed **9/9** after the transport
feedback edit. Final integrated verification is required after all parallel
edits settle. Live shell reload, multi-monitor acceptance, and before/after
frame-time measurements remain outstanding.

## Parallel control-center polish — 2026-11-13

The Dashboard now fades and moves the active tab content by 10px during a
210ms enter transition, with input disabled until the new content is usable.
Changing away from Home dismisses its Wi-Fi/Bluetooth drawer and releases its
input immediately, while the old drawer width fades out and its lazy content
is released. Native offscreen Dashboard motion tests passed 23/23.

Quick Settings now coalesces rapid brightness input into the newest queued
percentage while its `brightnessctl` write process is busy. An isolated real
Quickshell test using a fake `brightnessctl` command confirmed the last
brightness value is applied and redundant intermediate writes are skipped;
the focused Dashboard tests passed 19/19. This does not benchmark real device
latency or prove monitor-specific brightness support.

The Bar adds brief color transitions to its interactive surfaces; tray icons
show a consistent hover highlight. Tray taps dispatch primary activation on
left click, secondary activation on middle click, and a menu only on right
click when `hasMenu`. A regression exercises all three routes and the no-menu
case. Context7's Quickshell 0.3.1 API documents `secondaryActivate()` and
`hasMenu` on `SystemTrayItem`; installed Quickshell is 0.3.2, so a real
Wayland click check remains required. No live shell reload was performed.

Existing `Tokens.qml` already consumes wallpaper-adaptive semantic colors
from `adaptive-theme.json`; no duplicate palette extractor was introduced.

After integrating all parallel patches, `python3 -m unittest discover -s
tests -q` passed **287/287** in 93.838 seconds. `tests/validate.py` and
`git diff --check` passed. These checks exercise the source and isolated
offscreen Quickshell harnesses; the running desktop has not reloaded the new
configuration. Only one physical display was available for earlier checks.
