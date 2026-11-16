# Balanced Control Center Spring Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Finish the approved balanced spring effect throughout the existing Control Center and its menus.

**Architecture:** Preserve the inherited shared pill/drawer springs and their lifecycle fixes. Use Qt Controls' existing popup transitions for the remaining action-menu scale spring and quick contraction; never resize its content during animation.

**Tech Stack:** Quickshell, Qt Quick/Controls, Python unittest and the existing native Qt harness pattern. No new dependencies.

---

### Task 1: Preserve the active baseline

**Files:** `island/Island.qml`, `island/IslandShape.qml`, `dashboard/Dashboard.qml`,
`dashboard/ConnectivityCenter.qml` under `config/quickshell/rice-shell/`, plus
`tests/test_dashboard_motion.py` and `tests/test_island_mask_regression.py`.

1. Resolve the live link and record the active Git revision/WIP.
2. Create an ignored isolated worktree at active HEAD; back up and copy only the
   six inherited modified files without changing the original checkout.
3. Verify the copied files' hashes and run the existing focused tests.
4. Record scope/ownership in the tracker. Commit only the approved design/plan.

### Task 2: Complete action-menu spring motion (@test-driven-development)

**Modify:** `config/quickshell/rice-shell/dashboard/ActionMenu.qml`.
**Create:** `tests/test_action_menu_motion.py`.

1. Create an offscreen native Qt test loading the real ActionMenu and token/item
   fixtures. Sample popup content's parent scale and opacity during entry, exit
   and a mid-exit reopen. Assert peak scale exceeds 1 slightly (less than 1.02),
   finishes exactly at 1, contracts during exit, and closes/releases focus.
2. Run `python3 -m unittest discover -s tests -p 'test_action_menu_motion.py' -v`.
   Confirm failure is missing spring overshoot/contraction, not a fixture error.
3. Set `transformOrigin: Basic.Popup.TopRight`. Replace entry's scale
   NumberAnimation with `SpringAnimation { property: "scale"; from: 0.9; to: 1;
   spring: 4.0; damping: 0.34; epsilon: 0.001 }`. Retain the existing opacity
   animation. Add a 140ms exit scale animation to 0.94, without a `from` value,
   alongside the existing 90ms fade.
4. Run the focused test again and inspect native warnings. Adjust only if actual
   motion/lifecycle evidence identifies a problem.
5. Review specification first, then code quality; fix any findings before Task 3.

### Task 3: Verify and preview (@verification-before-completion)

1. Run `python3 -m unittest discover -s tests -q`, `python3 tests/validate.py`,
   and `git diff --check`; record real failures/skips, never infer visual acceptance.
2. Run `./install.sh --dry-run --no-state quickshell`, then install only that
   component. Preserve the original checkout and installer backup.
3. Reload the existing rice instance using its public IPC; verify health and new
   log diagnostics, then check `hyprctl configerrors`.
4. Use public IPC to open/close Home and Wi-Fi/Bluetooth/Hotspot menus without
   toggling services or desktop input. Capture the real Wayland animation and
   settled frames. Restore a closed dashboard after verification.
5. Update this task's tracker/evidence and report changed files, rollback command,
   and limits (no physical mouse/device/multi-monitor or pixel-identical iOS claim).
