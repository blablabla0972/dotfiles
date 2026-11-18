# Notification Actions and D-Bus Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Add safe, real Quickshell D-Bus notification actions to the Center and popup/island.

**Architecture:** Keep live `Notification` objects in `Notifications.qml` keyed by id. Store only action labels and ids in `DesktopControls.notificationHistory`, then let Center and island resolve the live object before invoking an action once. Keep inline replies disabled.

**Tech Stack:** Quickshell 0.3.1 QML, QtQuick, Python `unittest`, repository validator.

---

### Task 1: Add regression coverage

**Files:**
- Modify: `tests/test_notifications_lifecycle.py` or create `tests/test_notification_actions.py`
- Test: `config/quickshell/rice-shell/overlays/Notifications.qml`, `config/quickshell/rice-shell/dashboard/NotificationCenter.qml`, `config/quickshell/rice-shell/island/Island.qml`, `config/quickshell/rice-shell/services/DesktopControls.qml`

**Step 1:** Add static assertions for action capability flags, action metadata, live-registry lookup, invoke-once guard, close/expiry unregister, and history serialization.

**Step 2:** Run the focused test and confirm it fails against the current implementation.

### Task 2: Implement live action lifecycle

**Files:**
- Modify: `config/quickshell/rice-shell/overlays/Notifications.qml`
- Modify: `config/quickshell/rice-shell/services/DesktopControls.qml`

**Step 1:** Add a live registry keyed by notification id, action metadata extraction, and an idempotent `invokeNotificationAction` function.

**Step 2:** Enable `actionsSupported` and keep `inlineReplySupported` false. Register notifications before publishing and unregister on close, expiry, and disposal.

**Step 3:** Extend history entries with serializable action labels and identifiers only.

**Step 4:** Run focused tests, validator, and QML/native checks.

### Task 3: Render actions in both surfaces

**Files:**
- Modify: `config/quickshell/rice-shell/dashboard/NotificationCenter.qml`
- Modify: `config/quickshell/rice-shell/island/Island.qml`
- Modify: `config/quickshell/rice-shell/shell.qml`

**Step 1:** Pass notification id and action metadata into the island alert.

**Step 2:** Render buttons only when action metadata exists, with one click invoking the live registry handler and dismissing the visual alert.

**Step 3:** Render Center buttons from history metadata and leave historical entries inert after the live object is gone.

**Step 4:** Run focused and full regression suites, then review `git diff --check` and `git status --short`.

### Task 4: Verify without touching the live desktop

**Files:**
- No source changes

**Step 1:** Run `python3 tests/validate.py`.

**Step 2:** Run `python3 -m unittest discover -s tests -q`.

**Step 3:** Run available `qmllint` or native integration validation against the files, without `hyprctl reload`, shell restart, or installer commands.

**Step 4:** Report any unavailable real D-Bus or multi-monitor verification explicitly.
