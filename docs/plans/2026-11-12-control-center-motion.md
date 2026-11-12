# Control Center Motion Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Make the control center reveal smoothly without squeezing its content or losing rapid reopen requests.

**Architecture:** Animate one progress value, derive the shape and content appearance from it, and reveal fixed-size content through a clip. Keep the window mapped until closing actually completes; cancel pending opens when dismissed.

**Tech Stack:** Quickshell 0.3.1, Qt Quick/QML, Python unittest, installed Qt6 Quick/Qml/Test native harness.

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
       NumberAnimation {
           duration: dashboardWindow.expanded ? 300 : 200
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
4. Put `cardContent` inside a parent-sized clipped item. Give it width 760,
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
