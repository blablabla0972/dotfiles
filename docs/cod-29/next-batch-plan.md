# COD-29 Next Batch Plan: Production UI & Full Rice Shell Integration (Batch 2)

- **Document**: `docs/cod-29/next-batch-plan.md`
- **Worktree**: `/home/admin/Projects/dotfiles/.worktrees/cod-29`
- **Branch**: `feat/cod-29-top-edge-workspace-drag`
- **Date**: 2026-11-22
- **Author**: Teamwork Engineering (COD-29 Technical Systems & QA Specialist)
- **Status**: **PROPOSED & ACTIONABLE (Batch 2 Engineering Roadmap)**
- **Prerequisite**: Milestone 5 Foundation Verification (All Milestones 1–4 Gates Cleared)
- **Linear Issue**: [COD-29: Top-edge Workspace Drag (Hymission-inspired)](https://linear.app/codechinh/issue/COD-29/top-edge-workspace-drag-keo-cua-so-bang-super-len-mep-tren-dje-tha-vao)

---

## 1. Executive Summary & Batch 2 Mission

The foundational phase (Batch 1: Milestones 1–5) successfully proved the hybrid architecture (Option 3), verified bit-for-bit ABI compatibility, implemented the pure C++ state machine with 15/15 unit tests, resolved all IPC concurrency defects (C1–C5), and validated safe atomic drop dispatch (IT01–IT13) under a strict zero-impact safety contract.

**Batch 2 (Production UI & Full Rice Shell Integration)** transitions COD-29 from an isolated engineering foundation into a fully integrated, daily-driver desktop feature. The mission of Batch 2 is to:
1. Enable dynamic compositor runtime configuration without hardcoded values.
2. Wire `TopEdgeWorkspaceStrip.qml` into the active Quickshell Rice Shell environment.
3. Support arbitrary multi-monitor topologies with dynamic geometry tracking.
4. Deliver high-fidelity visual feedback, spring physics, and Noctalia token styling.
5. Provide user-facing controls in the Rice Shell Control Center with instant hot-reload.

---

## 2. Architectural Principles & Invariants for Batch 2

Throughout Batch 2, all implementations must uphold the following core invariants established in Batch 1:
- **The Single Owner Invariant**: The native C++ plugin (`libcod29_top_edge_drag.so`) remains the sole owner of gesture lifecycle, edge detection, dwell timing, and atomic window drop commitment. The Quickshell UI is strictly a presentation layer.
- **Pointer Grab Inviolability**: The Quickshell UI surface must never take pointer focus or steal pointer grabs (`WlrKeyboardFocus.None`, `exclusiveZone: 0`).
- **Compositor Crash Immunity (Hardening Rules H1–H3)**: All compositor hook entry points must remain `noexcept`, quarantine exceptions, capture pre-release window references, and cleanly abort on superseded releases.
- **Strict Default OFF**: The feature remains disabled by default until explicitly enabled by the user via configuration or the Control Center UI.

---

## 3. Work Breakdown Structure & Detailed Tasks

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BATCH 2 TASK ROADMAP                            │
├───────────────────────────────────┬────────────────────────────────────┤
│ Task 1: Dynamic Hyprland Config   │ Task 2: Active Rice Shell Runtime  │
│   - HyprlandAPI::addConfigValue   │   - shell.qml loader integration   │
│   - onConfigReload hooks          │   - Socket path auto-discovery     │
├───────────────────────────────────┼────────────────────────────────────┤
│ Task 3: Multi-Monitor Topologies  │ Task 4: Motion & Interactive FX    │
│   - Per-monitor strip anchors     │   - SpringAnimation card hover     │
│   - Hotplug dynamic re-anchor     │   - Window thumbnail ghost preview │
├───────────────────────────────────┴────────────────────────────────────┤
│ Task 5: Control Center Settings UI & Hot-Reload                        │
│   - Rice Shell Control Center toggle & parameter sliders               │
│   - Real-time IPC sync without restarting compositor                   │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Task 1: Hyprland Dynamic Configuration Registration & Hot-Reload Hooks

#### Objective
Replace hardcoded state machine parameters with native Hyprland config entries registered via `HyprlandAPI::addConfigValue`, enabling live hot-reloading without plugin unloads or compositor restarts.

#### Detailed Scope & Technical Specification
1. **Config Key Registration**:
   In `src/cod29/plugin_entry.cpp` (`PLUGIN_INIT`), register five plugin configuration variables under the `plugin:cod29:` namespace:
   ```cpp
   HyprlandAPI::addConfigValue(handle, "plugin:cod29:enabled", Hyprlang::CConfigValue((Hyprlang::INT)0));
   HyprlandAPI::addConfigValue(handle, "plugin:cod29:edge_tolerance", Hyprlang::CConfigValue((Hyprlang::FLOAT)4.0f));
   HyprlandAPI::addConfigValue(handle, "plugin:cod29:dwell_time_ms", Hyprlang::CConfigValue((Hyprlang::INT)80));
   HyprlandAPI::addConfigValue(handle, "plugin:cod29:exit_hysteresis", Hyprlang::CConfigValue((Hyprlang::FLOAT)28.0f));
   HyprlandAPI::addConfigValue(handle, "plugin:cod29:drop_follow", Hyprlang::CConfigValue((Hyprlang::INT)0));
   ```
2. **Dynamic Config Reload Hook**:
   Register a hook on `onConfigReload` using Hyprland's config manager event or signal:
   ```cpp
   static void onConfigReload() noexcept {
       try {
           static auto* const PENABLED = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(handle, "plugin:cod29:enabled")->getDataStaticPtr();
           static auto* const PTOL = (Hyprlang::FLOAT* const*)HyprlandAPI::getConfigValue(handle, "plugin:cod29:edge_tolerance")->getDataStaticPtr();
           static auto* const PDWELL = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(handle, "plugin:cod29:dwell_time_ms")->getDataStaticPtr();
           static auto* const PHYST = (Hyprlang::FLOAT* const*)HyprlandAPI::getConfigValue(handle, "plugin:cod29:exit_hysteresis")->getDataStaticPtr();
           static auto* const PFOLLOW = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(handle, "plugin:cod29:drop_follow")->getDataStaticPtr();

           Cod29::Config cfg{};
           cfg.enabled = **PENABLED != 0;
           cfg.edgeTolerance = **PTOL;
           cfg.dwellTimeMs = static_cast<uint64_t>(**PDWELL);
           cfg.exitHysteresis = **PHYST;
           cfg.dropFollow = **PFOLLOW != 0;

           g_pAdapter->getStateMachine().setConfig(cfg);
       } catch (...) {
           // Quarantine config parse failures
       }
   }
   ```
3. **Lua Dotfiles Bridge**:
   Expose config settings in `config/hypr/hyprland.lua` via `hypr.plugin.cod29 = { enabled = 0, ... }`.

#### Dependencies
- Hyprland header `hyprlang.hpp` and `PluginAPI.hpp`.

#### Risk Analysis & Mitigation
- **Risk**: Null pointer dereference if `getConfigValue` is called before config parsing completes.
- **Mitigation**: Guard all pointers with null checks and fallback to default safe struct values.

---

### Task 2: Active Rice Shell Runtime Integration

#### Objective
Load `TopEdgeWorkspaceStrip.qml` seamlessly into the active Quickshell Rice Shell session, managing its lifecycle and auto-discovering the compositor IPC socket.

#### Detailed Scope & Technical Specification
1. **Quickshell Loader Hook**:
   Integrate `TopEdgeWorkspaceStrip.qml` into `config/quickshell/rice-shell/shell.qml` via `Variants` scoped per monitor:
   ```qml
   Scope {
       Variants {
           model: Quickshell.screens
           delegate: Component {
               TopEdgeWorkspaceStrip {
                   targetScreen: modelData
               }
           }
       }
   }
   ```
2. **Robust Socket Auto-Discovery & Reconnect**:
   Refine `TopEdgeWorkspaceStrip.qml` IPC socket connection logic to dynamically poll for `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/cod29.sock` and establish automatic reconnection with exponential backoff if the plugin is unloaded or reloaded.
3. **Lazy Allocation**:
   Keep the QML panel lightweight when hidden: the visual strip container remains collapsed ($y = -\text{height}$) until `SHOW_STRIP` is received, consuming zero GPU rasterization cycles during regular desktop use.

#### Dependencies
- Task 1 (Plugin operational and socket listening).
- Quickshell 0.3.2 runtime with Wayland LayerShell support.

#### Risk Analysis & Mitigation
- **Risk**: LayerShell surface flickering or visual glitches during rapid show/hide events.
- **Mitigation**: Use smooth QML opacity and coordinate interpolation without destroying the underlying surface.

---

### Task 3: Multi-Monitor Topologies & Dynamic Output Geometries

#### Objective
Deliver robust gesture handling across complex multi-monitor setups (horizontal arrangements, vertical stacks, mixed DPI, negative virtual desktop origins, and dynamic display hotplugging).

#### Detailed Scope & Technical Specification
1. **Per-Monitor Active Output Detection**:
   In `src/cod29/plugin_entry.cpp:onMouseMove`, dynamically resolve the monitor containing the pointer coordinates using `::State::monitorState()->monitors()`. Query the monitor's physical and logical boundaries:
   ```cpp
   const auto box = pActiveMon->logicalBox();
   const OutputRect output{box.x, box.y, box.w, box.h};
   ```
2. **Top-Edge Detection on Stitched/Vertical Monitors**:
   When monitors are stacked vertically (e.g. Display B directly below Display A), dragging up on Display B will cross the boundary into Display A rather than arming the top edge of Display B unless Display B's top edge is an outer physical display boundary.
   - Implement topology awareness in `StateMachine`: allow configuring per-monitor edge arming or restrict edge detection to the uppermost monitor edge in a vertical stack.
3. **Monitor Hotplug Resilience**:
   Listen to `Event::bus()->m_events.monitor.added` and `Event::bus()->m_events.monitor.removed`. If a monitor is removed during an active drag, trigger `onCancel(CancelReason::MonitorRemoved)`, resetting the state machine and dismissing any orphan strips.

#### Dependencies
- Task 1, Task 2.

#### Risk Analysis & Mitigation
- **Risk**: Coordinate precision loss or scaling artifacts on fractional scaling monitors (e.g., 125%, 150%).
- **Mitigation**: Use compositor logical coordinates directly, which already account for output scale factors.

---

### Task 4: Interactive Drag Preview Animations & Fluid Gestures in QML

#### Objective
Elevate the visual presentation of `TopEdgeWorkspaceStrip.qml` to match the refined aesthetic of the Rice Shell desktop (Noctalia design tokens, spring physics, blurred surfaces, active window miniature ghost).

#### Detailed Scope & Technical Specification
1. **Spring Physics & Motion Curves**:
   Incorporate Rice Shell motion curves (`Tokens.qml`) for the strip entry and exit:
   ```qml
   Behavior on y {
       SpringAnimation {
           spring: 4.5
           damping: 0.32
           epsilon: 0.25
       }
   }
   ```
2. **Drop Target Card Highlighting**:
   When `TARGET_CHANGED <wsId>` is received via IPC:
   - Apply a dynamic glow effect and subtle scale transformation ($1.0 \to 1.06$) to the hovered workspace card.
   - Display a distinct accent indicator using `Tokens.palette.accent` / `Tokens.palette.primary`.
   - If hovering over the current source workspace, display a dimmed or neutral badge indicating that release will execute a NO-OP.
3. **Window Miniature / Icon Ghost**:
   Query active window metadata via Hyprland IPC or Quickshell window model to display the dragged window's app icon and title floating above the hovered workspace card, providing immediate visual confirmation of the drop payload.

#### Dependencies
- Task 2 (Quickshell Rice Shell integration).
- `config/quickshell/rice-shell/theme/Tokens.qml`.

#### Risk Analysis & Mitigation
- **Risk**: Animation frame drops during heavy compositor load.
- **Mitigation**: Utilize hardware-accelerated QML shader effects (`FastBlur`, `LayerEffect`) and avoid CPU-bound JavaScript execution in animation loops.

---

### Task 5: User Settings UI in Rice Shell Control Center

#### Objective
Add an intuitive configuration section for COD-29 within the Rice Shell Control Center settings panel, enabling non-technical users to customize gesture behavior with instant visual feedback.

#### Detailed Scope & Technical Specification
1. **Control Center UI Component**:
   Add `TopEdgeDragSettings.qml` inside `config/quickshell/rice-shell/dashboard/pages/`:
   - **Master Toggle**: Enable / disable top-edge workspace drag (`plugin:cod29:enabled`).
   - **Dwell Time Slider**: Adjust dwell delay between $60\text{ms}$ (responsive) and $120\text{ms}$ (strict flick filtering), default $80\text{ms}$.
   - **Edge Tolerance Slider**: Adjust physical top-edge capture height between $2\text{px}$ and $8\text{px}$, default $4\text{px}$.
   - **Drop Follow Toggle**: Choose whether window focus follows the dropped window to the target workspace (`follow = false` vs `follow = true`).
2. **IPC Settings Persistence**:
   Save user adjustments to `~/.config/noctalia/settings.toml` and emit `hyprctl seterror` or dynamic config updates to synchronize live plugin parameters instantly.
3. **Interactive Visual Test Canvas**:
   Provide a mini interactive preview canvas inside the settings page showing a simulated workspace strip reacting to test slider values.

#### Dependencies
- Task 1 (Dynamic configuration parameters).
- Task 2 (Rice Shell integration).

#### Risk Analysis & Mitigation
- **Risk**: Desynchronization between Control Center UI state and Hyprland runtime state.
- **Mitigation**: Read current live values directly from `hyprctl getoption plugin:cod29:...` on page load.

---

## 4. Dependencies & Execution Sequence Matrix

| Task | Description | Hard Prerequisites | Concurrent Tasks | Estimated Effort |
|---|---|---|---|---|
| **Task 1** | Dynamic Hyprland Config Registration | Batch 1 (M1–M5) complete | Task 2 | 2 Days |
| **Task 2** | Active Rice Shell Runtime Integration | Batch 1 complete | Task 1 | 2 Days |
| **Task 3** | Multi-Monitor Topologies & Hotplug | Task 1, Task 2 | Task 4 | 3 Days |
| **Task 4** | Interactive Drag Preview & Spring FX | Task 2 | Task 3 | 3 Days |
| **Task 5** | Control Center Settings UI & Hot-Reload| Task 1, Task 2 | Task 3, Task 4 | 2 Days |

---

## 5. Verification Criteria & Batch 2 Safety Gates

To ensure uncompromising stability, Batch 2 execution will be governed by five sequential quality gates:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BATCH 2 QUALITY GATES                           │
├─────────┬───────────────────────────────┬──────────────────────────────┤
│ Gate 1  │ Config & Hot-Reload Gate      │ addConfigValue & hot-reload  │
│ Gate 2  │ Rice Shell Runtime Gate       │ LayerShell loading & socket  │
│ Gate 3  │ Multi-Monitor Geometry Gate   │ Multi-display & hotplug test │
│ Gate 4  │ Motion & Animation Gate       │ 60fps spring physics audit   │
│ Gate 5  │ Final Production Release Gate │ Full regression & E2E audit  │
└─────────┴───────────────────────────────┴──────────────────────────────┘
```

### Gate 1: Config & Hot-Reload Validation Gate
- **Criteria**:
  - `plugin:cod29:enabled` defaults to `0` (OFF).
  - Toggling `enabled` from `0` to `1` via `hyprctl` or config file instantly activates gesture tracking without restarting compositor.
  - Dynamically altering `dwell_time_ms` and `edge_tolerance` reflects immediately in state machine behavior.
  - Malformed or out-of-range config values are safely clamped without crashes.

### Gate 2: Rice Shell Runtime Integration Gate
- **Criteria**:
  - `TopEdgeWorkspaceStrip.qml` instantiates cleanly on all active screens under `quickshell`.
  - Zero pointer grab conflicts: `WlrKeyboardFocus.None` verified via Wayland protocol traces.
  - IPC socket auto-reconnect succeeds after plugin exit/reload cycles.
  - Strip hides immediately when gesture is cancelled.

### Gate 3: Multi-Monitor & Edge Geometry Validation Gate
- **Criteria**:
  - Tested on at least 2 distinct monitor geometries (side-by-side and vertical/stacked).
  - Strip displays on the correct active monitor without rendering ghost panels on inactive displays.
  - Negative origin offsets correctly handled.
  - Dynamic monitor disconnect during active drag triggers clean cancellation without dangling pointer grabs.

### Gate 4: Motion & Animation Performance Gate
- **Criteria**:
  - Entry and exit spring animations render smoothly at display refresh rate ($60\text{Hz} / 120\text{Hz} / 144\text{Hz}$) with zero dropped frames.
  - Memory consumption of Quickshell process increases by $< 8\text{MB}$ with the strip module loaded.
  - Card hover scale and Noctalia accent colors adhere strictly to design system tokens.

### Gate 5: Final Production Release & User Acceptance Gate
- **Criteria**:
  - 100% of unit tests (L01–L15) and integration tests (IT01–IT13) continue to pass.
  - Full E2E suite passes in nested testing environment.
  - Zero regressions in existing desktop keybindings (`Super+Escape`, `Super+Tab`, `Super+LMB`).
  - Formal sign-off by Technical Systems Specialist, Reviewer, and Forensic Auditor.

---

## 6. Summary & Recommendations

Batch 1 established a battle-tested, concurrency-hardened, and ABI-verified foundation. Batch 2 provides the concrete roadmap to transform this foundation into a delightful, fluid desktop feature.

**Recommendation**: Proceed immediately to Batch 2 planning authorization upon merge of branch `feat/cod-29-top-edge-workspace-drag` into `main`.
