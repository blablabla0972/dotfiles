# Control Center Motion Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Make the control center reveal smoothly without squeezing its content or losing rapid reopen requests.

**Architecture:** Animate one progress value, derive the shape and content appearance from it, and reveal fixed-size content through a clip. Keep the window mapped until closing actually completes; cancel pending opens when dismissed.

**Tech Stack:** Installed Quickshell 0.3.2, Qt Quick/QML 6.12.0, Python unittest, installed Qt6 Quick/Qml/Test native harness.

---

### Task 1: Native motion regressions

**Files:**
- Create: `tests/test_dashboard_motion.py`
- Read: `tests/test_qml_input.py` (existing native test pattern)
- Read: `config/quickshell/rice-shell/dashboard/Dashboard.qml`
- Read: `config/quickshell/rice-shell/island/IslandShape.qml`

1. Build an isolated `Window` from the actual Dashboard source by removing only
   Quickshell surface configuration; copy the actual IslandShape. Stub the
   hardware-backed tab bodies and palette singleton, not motion or timers.
2. Expose content dimensions, parent clip dimensions, content offset/opacity,
   panel geometry and expanded/visible state to a small Qt6 executable.
3. Sample the opening/closing animation; assert constant content 760 × 440,
   intermediate reveal geometry, visible movement/fade and final panel size.
4. Assert a close interrupted by toggle remains open, and dismissing before the
   initial 16 ms opening does not leave a hidden expanded panel. Check the
   existing sidecar opens and closes without changing the fixed content size.
5. Run `python3 -m unittest discover -s tests -p test_dashboard_motion.py -v`.
   Expected red: existing animated content dimensions and lost reopen.

### Task 2: Minimal Dashboard implementation

**Files:**
- Modify: `config/quickshell/rice-shell/dashboard/Dashboard.qml`
- Test: `tests/test_dashboard_motion.py`

1. Add the reversible progress animation:

   ```qml
   property real revealProgress: expanded ? 1 : 0
   Behavior on revealProgress {
       id: revealBehavior
       NumberAnimation {
           duration: revealBehavior.targetValue === 1 ? 300 : 200
           easing.type: Easing.OutCubic
       }
   }
   onRevealProgressChanged: {
       if (!expanded && revealProgress === 0) visible = false;
   }
   ```

2. Reopen if visible but closing; do not reset geometry. On dismissal stop
   `openTimer`, clear the sidecar, set `expanded=false`, and hide immediately if
   progress is already zero. Remove `closeTimer`.
3. Derive top margin `42 * revealProgress`, pill width
   `200 + 560 * revealProgress`, and pill height `440 * revealProgress`.
   Set this IslandShape instance's width/height animation durations and overshoot
   to zero. Remove the independent top-margin behavior.
4. Reuse `morphContainer` as the parent-sized clipped item. Give `cardContent` width 760,
   height 440, horizontal centering, `y: -18 * (1 - revealProgress)` and opacity
   `Math.max(0, (revealProgress - 0.15) / 0.85)`. Remove its top anchor and
   independent y/opacity behaviors. Keep the inner layout intact.
5. Run the native motion test again. Expected green. Review spec compliance
   (stable layout and existing appearance) before code quality (one animation,
   no new dependencies, timer races covered).

### Task 3: Verification and live preview

**Files:**
- Modify: `docs/plans/task.md`
- Update: this plan with observed verification limits

1. Run `python3 tests/validate.py`,
   `python3 -m unittest discover -s tests -q`, and `git diff --check`.
   Investigate failures; reproduce existing failures on the original checkout
   rather than fixing unrelated behavior silently.
2. Compare native `qmllint` diagnostics for Dashboard with the original, if the
   installed Qt tool is available; report baseline warnings accurately.
3. Run `./install.sh --dry-run --no-state quickshell`, then preview only that
   component with `./install.sh --no-state quickshell`. Restart only the selected
   rice-shell instance, not other desktop services.
4. Exercise opening, closing, quick reopen, tabs and sidecars via the existing
   rice IPC. Capture the panel with `grim`; read QML logs and run
   `hyprctl configerrors`. No power, wallpaper or theme actions.
5. Review the final diff, document exact test results and rollback path, and
   retain the feature branch/worktree without merging or pushing.

## Observed verification

- Final runtime version check: `qs --version` reports Quickshell 0.3.2; the
  installed Qt6 Quick/Qml/Test development modules are 6.12.0. The machine skill's
  0.3.1 description was outdated; the used APIs were validated on this runtime.
- Six native motion regressions passed after failing against the original.
  Evidence: `/tmp/opencode/control-center-motion-before.json` and `-after.json`.
- Closing initially reproduced a Qt binding-order problem when duration depended
  on `expanded`. Selecting duration with `Behavior.targetValue`, which Qt sets
  before starting its animation, made the 200 ms closing regression pass.
- Reused the existing `morphContainer` as the clip rather than adding a wrapper.
- Validator and diff checks pass. Full suite: 245/246 pass, no skips. The unchanged
  `test_interactive_network_drawers` demands `nmcli` despite the native networking
  implementation; the original checkout reproduces this same failure (10/11 of
  its dashboard tests pass). No unrelated networking code/test was changed.
- Native Dashboard qmllint: original and candidate both exit 0, three warnings,
  zero errors. Warnings concern PanelWindow metadata and existing close-button
  layout dimensions, not the new motion.
- Independent spec review: SPEC PASS. External quality review could not finish
  because its separate advisor login expired; structured local lifecycle,
  clipping/input and test-quality review found no introduced blocker.
- Live preview installed only `quickshell`; new rice-shell PID 205044 reports
  `Configuration Loaded`. Dashboard logs contain zero warnings/errors;
  `hyprctl configerrors` is empty. The existing Island waveform `index` warning
  and host portal/accessibility warnings remain unrelated and unchanged.
- Live native checks pass 14/14: open/close, all three tabs, both sidecars, three
  interrupted-close/reopen cycles and immediate IPC dismissal. Early dismissal
  *before* the 16 ms timer is covered by the native in-process regression;
  separate CLI calls can exceed that delay, so the live check allows closing
  to complete. Evidence: `/tmp/opencode/control-center-live-verified.json`.
- Initial live probes incorrectly counted every Quickshell overlay and assumed
  compositor surface addresses persisted across remaps. The corrected probe
  discovers each newly mapped Dashboard surface, distinguishes other overlays
  and observes its lifetime. These were verification-harness corrections, not
  additional production changes.
- Screenshots inspected: `/tmp/opencode/control-center-verified-opening.png`,
  `control-center-verified-result.png`, `control-center-verified-system.png`,
  `control-center-verified-config.png`, `control-center-verified-wifi.png`,
  and `control-center-verified-bluetooth.png`. These demonstrate real rendered
  content/reveal and final layout, not an FPS or subjective user acceptance claim.

## Preview and rollback

The live link resolves to
`/home/admin/Projects/dotfiles/.worktrees/control-center-motion/config/quickshell`.
Installer backup:
`~/.config/backups/dotfiles-20261112-234015-W8TR7F/.config/quickshell`.
The former `quickshell` worktree and its unrelated task-tracker changes remain
intact. No other components, generated palette outputs or runtime state changed.

To restore the previous Quickshell config, run from
`/home/admin/Projects/dotfiles/.worktrees/quickshell`:

```bash
./install.sh --dry-run --no-state quickshell
./install.sh --no-state quickshell
qs kill --pid 205044
qs -d -p /home/admin/.config/quickshell/rice-shell
```

The PID above belongs to this preview; confirm the current selected instance
before stopping it if it has since restarted. Preserve this feature worktree;
no merge or push was requested.

## User-authorized Wi-Fi test follow-up

After the initial delivery, the user explicitly requested fixing the remaining
test failure. `tests/test_dashboard_control_center.py` now checks the existing
native `Quickshell.Networking` import, Wi-Fi device enumeration, scanning binding,
PSK connection, regular connection and disconnect actions instead of demanding
the obsolete `nmcli` backend. Existing password, Bluetooth and sidecar assertions
remain intact. No production networking or animation behavior changed.

Fresh verification: dashboard tests 11/11 pass; full suite 246/246 passes in
40.149 s without skips. Seven read-only source mutations each removed one native
wiring token, and the repaired test rejected all seven. Tracked-file validation
and `git diff --check` also pass. The earlier 245/246 result above records the
pre-follow-up baseline, not the current result.
