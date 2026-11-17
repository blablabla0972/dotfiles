# Wi-Fi Drawer Smoothness Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Remove avoidable CPU work from Wi-Fi drawer updates and keep scans out of the open/close animation.

**Architecture:** `WifiDrawer.qml` will create one sorted snapshot and bucket it in one pass. `Dashboard.qml` passes side-drawer state through `ConnectivityCenter.qml`; `WifiDrawer.qml` schedules scans only while open and stops owned scans as soon as closing starts.

**Tech Stack:** Quickshell 0.3.2, QtQuick/QML, Quickshell.Networking.

---

### Task 1: Collapse repeated Wi-Fi list calculations

**Files:**
- Modify: `config/quickshell/rice-shell/dashboard/WifiDrawer.qml:24-114`

**Step 1: Replace repeated derivations**

Create one `networkSnapshot` binding that decorates each network with lowercase name and sort fields, sorts once, then returns `all`, `connected`, `known`, and `nearby`. Keep existing `networks`, `connectedNetwork`, `knownNetworks`, and `nearbyNetworks` properties as aliases to preserve callers.

**Step 2: Keep existing behavior guards**

Retain current device, hotspot, radio, selection, and connection checks. Add drawer-open guards only to scan scheduling and scanner ownership.

### Task 2: Remove scan work from close animation

**Files:**
- Modify: `config/quickshell/rice-shell/dashboard/Dashboard.qml:399-404`
- Modify: `config/quickshell/rice-shell/dashboard/ConnectivityCenter.qml:7-142`
- Modify: `config/quickshell/rice-shell/dashboard/WifiDrawer.qml:116-205,318-356,582-587`

**Step 1: Pass drawer visibility**

Add `drawerOpen` to `ConnectivityCenter`, bind it from `dashboardWindow.sideDrawerOpen`, and pass it into `WifiDrawer` through its Loader source component.

**Step 2: Schedule scan after open**

Add one short single-shot timer. Replace lifecycle-triggered immediate `startScan()` calls with a guarded schedule; re-check visibility, drawer state, adapter, radio, hotspot, and station mode before starting.

**Step 3: Stop on close**

Stop the delayed timer and owned scanner when `drawerOpen` becomes false. Keep manual refresh behavior and existing timer semantics.

### Task 3: Verify runtime

**Files:**
- Check: `config/quickshell/rice-shell/dashboard/WifiDrawer.qml`
- Check: `config/quickshell/rice-shell/dashboard/ConnectivityCenter.qml`
- Check: `config/quickshell/rice-shell/dashboard/Dashboard.qml`

**Step 1: Syntax/runtime smoke check**

Run `timeout 8s qs -p /home/admin/.config/quickshell/rice-shell 2> /tmp/rice-shell-wifi-check.log`; inspect only warnings/errors, then leave the existing daemon untouched if the foreground check cannot start.

**Step 2: Diff check**

Run `git diff --check` and confirm no unrelated files changed. Existing user edits in `Bar.qml`, `Dashboard.qml`, `Island.qml`, and `IslandShape.qml` must remain intact.

**Step 3: Commit implementation**

Commit only the Wi-Fi drawer files and plan tracker row with an imperative subject.
