# Architecture Decision Record (ADR): COD-29 Top-Edge Workspace Drag for Rice Shell

- **Status**: ACCEPTED
- **Decision Date**: 2026-11-22
- **Author**: Teamwork Engineering (COD-29 Foundation Worker)
- **Target Subsystem**: Hyprland Native Plugin & Quickshell Rice Shell Integration
- **Target Worktree**: `/home/admin/Projects/dotfiles/.worktrees/cod-29`
- **Target Branch**: `feat/cod-29-top-edge-workspace-drag`
- **Linear Issue**: [COD-29: Top-edge Workspace Drag (Hymission-inspired)](https://linear.app/codechinh/issue/COD-29/top-edge-workspace-drag-keo-cua-so-bang-super-len-mep-tren-dje-tha-vao)
- **Selected Architecture**: Option 3 — Hybrid Architecture (Native C++ State Machine & Hook Plugin + Quickshell Visual IPC Bridge)

---

## 1. Executive Summary & Context

### 1.1 Context and Problem Statement
In the Rice desktop environment (running on Arch Linux / CachyOS with Hyprland 0.57.2 and Quickshell 0.3.2), moving windows between workspaces currently relies on keyboard shortcuts (`Super + Shift + [1..5]` or `Super + Shift + Alt + [1..5]` for silent move). While keyboard workflows are efficient, modern desktop environments (e.g., macOS Mission Control, GNOME Shell, and upstream Hyprland plugins like Hymission) provide a fluid spatial drag-and-drop gesture:
> When dragging any window using the global mouse move binding (`Super + Left Mouse Button`), dragging the cursor up to the physical top edge of the display reveals a horizontal workspace strip. Dropping the window onto a target workspace card transfers the window into that workspace immediately (`follow = false`), without altering the active desktop focus or disturbing ongoing keyboard interactions.

### 1.2 Core Technical Challenges
Implementing this gesture cleanly within the Hyprland / Quickshell ecosystem entails five major technical constraints:
1. **Pointer Grab Inviolability**: Hyprland's native window drag (`hl.dsp.window.drag()`, `mouse:272`) initiates an internal compositor pointer grab (`MBIND_MOVE`). If an external client or layer-shell surface takes pointer focus or steals the grab, the native drag operation aborts or leaves the pointer in a corrupted state.
2. **Physical Edge Detection vs. Bar Reserved Zone**: In Rice Shell, `Bar.qml` occupies the top 40px of the screen with `exclusiveZone: 40`, setting Hyprland's monitor reserved area to `reserved: [0, 40, 0, 0]`. Edge detection must trigger against the physical logical screen boundary ($y \le \text{mon.y} + \text{tolerance}$), completely ignoring the 40px reserved bar area.
3. **Atomic Two-Phase Release**: The window move must commit atomically upon mouse button release. If the move dispatcher is executed prematurely before native drag completion, compositor layout corruption or invalid pointer coordinates can occur.
4. **Keybinding Safety**: In Rice Shell, `Super + Escape` is actively bound to `cancelWindowSwitcher` with a fallback to `hyprctl kill` (interactive window kill mode). Drag cancellation must be strictly internal and must never synthesize or broadcast `Super + Escape`.
5. **No-Op Policy for Same-Workspace Drop**: Dropping a window onto its currently assigned workspace card must be a strict NO-OP (no repositioning, no layout jitter, no focus shift).

---

## 2. Comparative Analysis of the 4 Architecture Options

We conducted a thorough architectural trade-off analysis across four candidate designs.

| Criterion | Option 1: Fork Hymission Controller | Option 2: Standalone Native C++ Plugin | Option 3: Hybrid (Native State + Quickshell UI) | Option 4: Pure Quickshell / IPC-only |
|---|---|---|---|---|
| **ABI Surface Area** | Extremely High (15+ internal symbols) | Medium (5–8 internal rendering symbols) | **Minimal (1 hook + 1 public signal)** | Zero (IPC only) |
| **Pointer Grab Safety** | Vulnerable (tangled grab state) | Native internal (safe) | **Native passive (100% safe)** | **Infeasible (grab conflict)** |
| **UI Rendering & Polish** | Raw OpenGL immediate pass | Raw OpenGL / Cairo / Wayland | **Quickshell QML (Tokens.qml, Blur, Spring)** | Quickshell QML |
| **Theme Consistency** | Hardcoded colors / GL shader | Hardcoded C++ palette | **Direct Rice Shell Noctalia integration** | Direct Rice Shell Noctalia integration |
| **Code Footprint** | Massive (~1.2 MB C++, 239 files) | High (~3,000–5,000 lines C++/GL) | **Small (~450 lines C++ + ~300 lines QML)** | Medium (~600 lines QML/IPC) |
| **Licensing** | GPL-3.0 copyleft contagion | MIT / Dotfiles license | **MIT / Dotfiles license** | MIT / Dotfiles license |
| **Testability** | Complex, requires compositor | Requires mock OpenGL context | **100% Deterministic C++ State Machine (L01–L15)** | QML manual testing only |
| **Architectural Verdict** | **REJECTED** | **REJECTED** | **ACCEPTED (SELECTED)** | **REJECTED (INFEASIBLE)** |

---

### 2.1 Option 1: Fork Upstream Hymission Controller
- **Description**: Clone and adapt `src/stage_controller.cpp` and `src/hook_broker.hpp` from upstream Hymission (`https://github.com/gfhdhytghd/hymission`, commit `03ba0cf9b8742b91300ef5935f067289a21eb2a4`).
- **Detailed Evaluation**:
  - **Bloat & Complexity**: Hymission is a monolithic Mission Control suite (~1.2 MB C++ source) tightly coupled to its custom `OverviewController`, `TilesController`, and `HookBroker`.
  - **License Contagion**: Hymission is licensed under **GPL-3.0**. Importing or linking this code introduces copyleft licensing obligations into the dotfiles repository.
  - **Fragile ABI Footprint**: Hymission hooks over 15 internal, unversioned Hyprland symbols (including `CSpace::recheckWorkArea`, `CWorkspace::startAnim`, `CCompositor::closeWindow`, `Desktop::CGlobalWindowController::moveWindowToWorkspace`). A minor bump in Hyprland internals routinely breaks these private function signatures.
  - **Fundamental Architectural Mismatch**: Hymission Stage is designed as a *persistent vertical sidebar* that continuously modifies the desktop workarea via `recheckWorkArea` insets. COD-29, by contrast, requires a *transient horizontal strip* anchored at the top edge that appears only upon sustained top-edge hover.
  - **Same-Workspace Behavior**: Hymission's Stage explicitly repositions floating windows within the same workspace upon drop (`stage_controller.cpp:2890`), which contradicts the COD-29 strict NO-OP specification.
- **Verdict**: **REJECTED**. Unacceptable maintenance overhead, licensing contagion, and excessive ABI fragility.

---

### 2.2 Option 2: Standalone Native Hyprland Plugin (All C++ Rendering)
- **Description**: Build a dedicated, self-contained Hyprland C++ plugin that performs native input tracking, state evaluation, and direct OpenGL rendering within Hyprland's render pass (`RENDER_POST_WINDOWS` or custom layer).
- **Detailed Evaluation**:
  - **Rendering Overhead**: Implementing an aesthetically polished strip with workspace thumbnails, active window counts, spring animations, and typography requires building a full OpenGL/Cairo 2D rendering pipeline in C++ from scratch.
  - **Theme Divergence**: Rice Shell relies on dynamic Matugen color generation and centralized design tokens (`Tokens.qml`, Noctalia theme palette). A pure C++ plugin would either hardcode colors or require custom file parsers to read CSS/TOML theme files, creating visual inconsistencies whenever the user switches themes.
  - **Render Pipeline Fragility**: Hyprland's internal rendering pipeline undergoes frequent architectural churn (e.g., Aquamarine integration, render pass refactoring). Custom rendering hooks are the most frequent source of compositor crashes during upstream upgrades.
- **Verdict**: **REJECTED**. High implementation complexity with duplicate rendering infrastructure and elevated crash risk.

---

### 2.3 Option 3: Hybrid Architecture (Native C++ State Machine/Hook Plugin + Quickshell Visual IPC Bridge) — SELECTED
- **Description**: Implement a minimal native Hyprland C++ plugin to observe pointer movements and handle atomic release drop dispatch, coupled with a pure C++ state machine for gesture evaluation. The visual strip is rendered as a transient, non-grabbing Quickshell panel driven via UNIX domain socket IPC.
- **Detailed Evaluation**:
  - **Clean Separation of Concerns**:
    - **Native Plugin**: Input event observation, dwell timing, physical geometry calculation, atomic release interception, and window workspace transfer dispatch.
    - **Quickshell UI**: Visual strip presentation, card hover styling, Noctalia theme integration, smooth spring animations, and blur effects.
  - **Minimal ABI Surface**: The native plugin requires hooking **only 1 internal function** (`Layout::Supplementary::CDragStateController::dragEnd()`) and listening to **1 public signal** (`Event::bus()->m_events.input.mouse.move`).
  - **Single Owner Invariant**: The native state machine maintains absolute ownership over gesture lifecycle and drop commits. Quickshell acts strictly as a visual slave; it never takes pointer grabs and never invokes window movements asynchronously.
  - **Testability & Determinism**: The pure C++ state machine has zero compositor or graphics dependencies, enabling 100% deterministic unit testing (L01–L15) using standard compilers (`g++` / `clang++`).
  - **Safety by Default**: Feature flag `top_edge_drag_enabled` defaults strictly to `false` (OFF). When disabled, the plugin executes zero state changes and has zero impact on desktop behavior.
- **Verdict**: **ACCEPTED**. The optimal architecture for safety, maintainability, visual fidelity, and robust verification.

---

### 2.4 Option 4: Quickshell / IPC-only (No Native Plugin)
- **Description**: Implement the entire top-edge workspace drag mechanism in Quickshell QML using Hyprland IPC sockets (`socket2.sock` and `.socket.sock`), without any native C++ plugin.
- **Detailed Evaluation & Technical Infeasibility Proof**:
  - **Proof of Infeasibility 1 (No Global Cursor Streaming)**: Hyprland's event broadcast socket (`socket2.sock`) emits discrete events (e.g., `focusedmon`, `workspace`, `openwindow`), but **does not stream continuous pointer coordinates** during native `MBIND_MOVE` window drags.
  - **Proof of Infeasibility 2 (Pointer Grab Conflict)**: For a Wayland LayerShell surface (Quickshell) to receive pointer motion coordinates, it must claim pointer focus. However, during native window drag, Hyprland holds an exclusive internal pointer grab. If Quickshell attempts to take pointer focus, the compositor cancels the native drag, freezing or dropping the window prematurely.
  - **Proof of Infeasibility 3 (Race Conditions on Release)**: Emitting `hyprctl dispatch movetoworkspacesilent` from an external client on mouse release races against Hyprland's internal `dragEnd()` handler, frequently leading to floating window position corruption, ghost windows, or focus desynchronization.
- **Verdict**: **REJECTED AS TECHNICALLY INFEASIBLE**.

---

## 3. The Single Owner Invariant & Architecture Overview

```
                      +---------------------------------------+
                      |         HYPRLAND COMPOSITOR           |
                      |  [EventBus: input.mouse.move]         |
                      |  [CDragStateController::dragEnd()]    |
                      +-------------------+-------------------+
                                          |
                        (Passive pointer) | (Detour Hook)
                                          v
                      +---------------------------------------+
                      |       COD-29 NATIVE C++ PLUGIN        |
                      |  +---------------------------------+  |
                      |  |     Pure C++ State Machine      |  |
                      |  |  (Geometry, Dwell, Hysteresis)  |  |
                      |  +----------------+----------------+  |
                      +-------------------|-------------------+
                                          |
             +----------------------------+----------------------------+
             | IPC Event Notification                                  | Atomic Release Dispatch
             v                                                         v
+---------------------------+                         +-----------------------------------+
|     QUICKSHELL STRIP      |                         | Hyprland Window Controller        |
|  - WlrLayer.Overlay       |                         | - Call original dragEnd()         |
|  - keyboardFocus: None    |                         | - moveWindowToWorkspace(win, dest)|
|  - pointerFocus: None     |                         |   with follow = false             |
|  - Visual Reflection Only |                         +-----------------------------------+
+---------------------------+
```

### 3.1 Single Owner Invariant
To prevent state desynchronization, race conditions, and grab conflicts, the system enforces a strict **Single Owner Invariant**:
1. **Exclusive State Authority**: The native C++ state machine is the sole arbiter of gesture progression (`Idle` $\to$ `Dragging` $\to$ `EdgeArmed` $\to$ `StripOpen` $\to$ `HoverTarget` $\to$ `DropIntent` / `NativeReleaseOnly`).
2. **Visual Slave Contract**: Quickshell does not manage gesture timers, hit detection, or drag lifecycle. It merely displays or hides the workspace strip and highlights target cards based on IPC messages received from the native state machine.
3. **Passive Interaction**: Quickshell surfaces are configured with `keyboardFocus: None` and `exclusiveZone: 0`. The cursor remains captured by the native Hyprland grab at all times.
4. **Atomic Two-Phase Commit**:
   - Step 1: Upon mouse release, the native plugin captures the current drop target and dragged window token.
   - Step 2: The original `CDragStateController::dragEnd()` is invoked exactly once to reset native grab state and clean up internal layout offsets.
   - Step 3: If target workspace differs from source workspace, `Desktop::globalWindowController()->moveWindowToWorkspace(window, dest)` is dispatched immediately with `follow = false`.
   - Step 4: If target equals source or release occurred outside any card, zero workspace movement dispatch occurs (strict NO-OP).

---

## 4. State Machine Architecture & Transition Matrix

### 4.1 State Definitions
1. **`Idle`**: Resting state. No native drag active or feature flag disabled.
2. **`Dragging`**: Eligible native window drag active (`MBIND_MOVE`, threshold reached). Cursor is below the top edge trigger zone.
3. **`EdgeArmed`**: Cursor is within the physical top edge zone ($y \le \text{output.y} + \text{tolerance}$). Dwell timer (80ms) is ticking.
4. **`StripOpen`**: Dwell satisfied. Horizontal workspace strip is visible. Cursor is inside strip bounds but not over a specific card.
5. **`HoverTarget`**: Cursor is hovering over a specific workspace card in the strip.
6. **`DropIntent`**: Mouse button released over a different workspace card. Atomic drop commit is initiated.
7. **`NativeReleaseOnly`**: Mouse button released outside cards, released over source workspace (NO-OP), or released before dwell. Compositor drag ends normally without window move.
8. **`Cleanup`**: Ephemeral post-release state resetting tokens and timers before returning to `Idle`.

### 4.2 Transition Matrix

| Current State | Event / Trigger | Guard Condition | Next State | Emitted Action | Notes |
|---|---|---|---|---|---|
| `Idle` | `NativeDragBegin` | `enabled == true && mode == MBIND_MOVE && thresholdReached` | `Dragging` | `None` | Feature flag checked. If false, stays `Idle`. |
| `Dragging` | `PointerMotion` | $y \le \text{output.y} + \text{edgeTolerance}$ | `EdgeArmed` | `ArmEdge(t)` | Starts 80ms dwell timer. |
| `Dragging` | `NativeRelease` | Any | `NativeReleaseOnly` | `NativeEnd` | Normal drag release below edge. |
| `Dragging` | `Cancel` | Lock / unmap / destroy | `Idle` | `Reset` | Session cancelled. |
| `EdgeArmed` | `PointerMotion` | $y > \text{output.y} + \text{edgeTolerance}$ | `Dragging` | `DisarmEdge` | Quick flick away; cancels dwell. |
| `EdgeArmed` | `DwellSatisfied` | $\Delta t \ge 80\text{ms}$ at edge | `StripOpen` | `ShowStrip` | Strip opens; IPC sends `open` to Quickshell. |
| `EdgeArmed` | `NativeRelease` | Release during dwell | `NativeReleaseOnly` | `NativeEnd` | Normal release; strip never opens. |
| `EdgeArmed` | `Cancel` | Lock / unmap / destroy | `Idle` | `Reset` | Cancelled during arming. |
| `StripOpen` | `CardEnter(ws)` | Cursor inside card box | `HoverTarget` | `TargetChanged(ws)` | Card highlighted in UI. |
| `StripOpen` | `HysteresisExit` | $y > \text{output.y} + \text{height} + \text{hysteresis}$ | `Dragging` | `HideStrip` | Cursor retreated down; strip closes. |
| `StripOpen` | `NativeRelease` | Release in whitespace | `NativeReleaseOnly` | `HideStrip, NativeEnd` | Released outside cards; window stays in place. |
| `StripOpen` | `Cancel` | Lock / unmap / destroy | `Idle` | `HideStrip, Reset` | Emergency cleanup. |
| `HoverTarget` | `CardLeave` | Cursor leaves card | `StripOpen` | `TargetChanged(none)` | Unhighlights card; strip remains open. |
| `HoverTarget` | `CardEnter(other)` | Cursor enters other card | `HoverTarget` | `TargetChanged(other)` | Updates target workspace. |
| `HoverTarget` | `HysteresisExit` | $y > \text{output.y} + \text{height} + \text{hysteresis}$ | `Dragging` | `HideStrip, TargetChanged(none)` | Retreats past strip boundary. |
| `HoverTarget` | `NativeRelease` | `targetWs != sourceWs` | `DropIntent` | `PrepareDrop(target, win)` | **Committed Drop Intent**. |
| `HoverTarget` | `NativeRelease` | `targetWs == sourceWs` | `NativeReleaseOnly` | `HideStrip, NativeEnd` | **COD-29 NO-OP Policy**: Same-workspace drop. |
| `HoverTarget` | `Cancel` | Lock / unmap / destroy | `Idle` | `HideStrip, Reset` | Cancelled while hovering. |
| `DropIntent` | `CommitComplete` | Original `dragEnd` finished | `Cleanup` $\to$ `Idle` | `Reset` | Atomic move executed (`follow=false`). |
| `NativeReleaseOnly`| `ReleaseComplete` | Original `dragEnd` finished | `Cleanup` $\to$ `Idle` | `Reset` | Drag ended cleanly without move. |

---

## 5. Runtime Environment & ABI Verification

### 5.1 Compositor & System Baseline
Verification conducted on target machine on 2026-11-22:
- **Operating System**: Linux 6.x (CachyOS / Arch Linux base)
- **Running Hyprland Version**: `0.57.2`
- **Compositor Git Commit**: `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947 clean (VERSION: bump to 0.57.2)`
- **Installed Headers**: `/usr/include/hyprland` matching commit `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`
- **Build Toolchains**:
  - GCC / G++: `16.2.1 20260810`
  - Clang / Clang++: `23.1.5`
  - CMake: `4.5.0`
  - Ninja: `1.13.2`
  - Pkg-Config: `3.0.11`

### 5.2 Bit-for-Bit ABI Match
Hyprland enforces an exact ABI string check inside `PluginAPI.hpp`'s `__hyprland_api_get_client_hash()` against the running compositor's `__hyprland_api_get_hash()`:
$$\text{ABI String} = \text{COMMIT}\_\text{aq}\_\text{AQ}\_\text{hu}\_\text{HU}\_\text{hg}\_\text{HG}\_\text{hc}\_\text{HC}\_\text{hlg}\_\text{HLG}$$

Running compositor `hyprctl version -j` reports:
```
abiHash: 11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947_aq_0.16_hu_0.14_hg_0.6_hc_0.1_hlg_0.6
```

Inspection of `/usr/include/hyprland/src/version.h` defines:
```c
#define GIT_COMMIT_HASH    "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
#define AQUAMARINE_VERSION "0.16.0"
#define HYPRUTILS_VERSION  "0.14.3"
#define HYPRGRAPHICS_VERSION "0.6.0"
#define HYPRCURSOR_VERSION "0.1.13"
#define HYPRLANG_VERSION   "0.6.8"
```
Strip-patch algorithm yields:
$$\text{Header Hash} = \text{"11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947\_aq\_0.16\_hu\_0.14\_hg\_0.6\_hc\_0.1\_hlg\_0.6"}$$
**Verification Result: 100% exact bit-for-bit match.** Plugins compiled against installed headers will load without ABI mismatch errors.

### 5.3 Exported Dynamic Symbol Audit
Inspection of dynamic symbols in `/usr/bin/Hyprland` confirmed the required symbols are exported with `T` (global text):
1. `_ZN6Layout13Supplementary20CDragStateController7dragEndEv` (`CDragStateController::dragEnd()`) at `0x006b4f80`
2. `_ZN7Desktop22CGlobalWindowController20moveWindowToWorkspaceEN9Hyprutils6Memory14CSharedPointerI7CWindowEENS3_I12CHLWorkspaceEE` (`moveWindowToWorkspace`) at `0x00534930`
3. `_ZN11HyprlandAPI18createFunctionHookEPvS0_S0_` (`createFunctionHook`) at `0x007bef20`
4. Global variables: `g_layoutManager`, `g_pInputManager`, `g_pCompositor`

---

## 6. Rice Shell Compatibility & Keybinding Protection

### 6.1 Protection of Existing Desktop Keybindings
The dotfiles repository defines keybindings in `config/hypr/config/binds.lua`. The implementation strictly adheres to the following coexistence rules:
- **`Super + Escape` (Interactive Kill Mode)**:
  - Line 23: `hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("test \"$(qs ipc -p ~/.config/quickshell/rice-shell call rice cancelWindowSwitcher 2>/dev/null)\" = true || hyprctl kill"))`
  - In Rice, `Super + Escape` activates `hyprctl kill` (interactive cursor kill mode) if the window switcher is not active.
  - **Invariant**: The drag state machine MUST NEVER synthesize, simulate, or intercept `Super + Escape`. Cancellation on session lock or window unmapping is handled entirely via internal C++ state transitions.
- **`Super + Tab` (Rice Window Switcher)**:
  - Managed by Quickshell `WindowSwitcher.qml` with modifier tracking on keycodes 133 and 134.
  - **Invariant**: COD-29 operations do not consume or alter Tab keycodes.
- **`Super + mouse:272` (Window Move)**:
  - Line 95: `hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })`
  - Window drag operates under native `MBIND_MOVE`. COD-29 attaches passively without taking pointer focus.
- **`Super + mouse:273` (Window Resize)**:
  - Line 96: `hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })`
  - Window resize operates under `MBIND_RESIZE`. COD-29 state machine filters this out immediately (`mode != MBIND_MOVE`), remaining in `Idle`.

### 6.2 Top Bar Reserved Area & Edge Geometry
In `config/quickshell/rice-shell/bar/Bar.qml`:
```qml
PanelWindow {
    id: barRoot
    implicitHeight: 40
    exclusiveZone: 40
    WlrLayershell.layer: WlrLayer.Top
}
```
The bar claims 40px exclusive zone, causing Hyprland to report `reserved: [0, 40, 0, 0]` on `eDP-1`. Consequently, usable window space begins at $y = 40$.

**Physical Boundary Formula**:
The edge detection algorithm explicitly ignores `reserved[1]` (40px) and calculates against the monitor's physical logical origin:
$$\text{EdgeHit}(x, y) \iff (\text{mon.y} \le y \le \text{mon.y} + \text{edgeTolerance}) \land (\text{mon.x} \le x < \text{mon.x} + \text{mon.width})$$
- Default $\text{edgeTolerance} = 4\text{px}$ (configurable $0..6\text{px}$).
- If computed against usable work area ($y = 40$), the strip would erroneously trigger 40px down into the screen during normal window positioning near the top bar.

### 6.3 Layer Z-Order and Quickshell Strip Positioning
- Quickshell Top Bar is rendered at `WlrLayershell.layer: WlrLayer.Top`.
- The transient workspace strip is rendered at `WlrLayershell.layer: WlrLayer.Overlay` with `exclusiveZone: 0` and `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None`.
- This guarantees:
  1. The workspace strip visually renders **above** `Bar.qml`.
  2. The workspace strip does not alter screen layout insets (`exclusiveZone = 0`).
  3. The workspace strip does not steal keyboard focus from the active window.

---

## 7. Roadmap & Phasing (Phases B through E)

| Phase | Milestone | Scope & Deliverables | Gate Condition |
|---|---|---|---|
| **Phase A** | **Milestone 1** | • Worktree isolation at `.worktrees/cod-29`.<br>• Architecture Decision Record (`architecture-decision.md`). | Complete ADR authored and committed. |
| **Phase B** | **Milestone 2** | • Runtime ABI proof verification.<br>• Native drag spike in isolated nested Hyprland (`dragEnd` hook & `mouse.move` listener).<br>• Deliverable: `docs/cod-29/native-spike-results.md`. | Verified event ordering and safe detour hooking without grab loss. |
| **Phase C** | **Milestone 3** | • Pure C++ State Machine implementation (`top_edge_drag_logic.{hpp,cpp}`).<br>• Config feature flag `top_edge_drag_enabled` (default `false`).<br>• Deterministic unit test suite covering L01 through L15. | 100% L01–L15 tests pass deterministically. |
| **Phase D** | **Milestone 4** | • Conditional MVP: Minimal horizontal workspace strip QML component.<br>• IPC socket listener connecting native plugin to Quickshell.<br>• Window transfer dispatch (`follow = false`). | Successful end-to-end drag and drop in nested session. |
| **Phase E** | **Milestone 5** | • Safety verification across all existing keybindings.<br>• Test report (`docs/cod-29/foundation-test-report.md`).<br>• Next batch plan (`docs/cod-29/next-batch-plan.md`).<br>• Vietnamese executive delivery report. | All artifacts verified, zero regressions to live system. |

---

## 8. Conclusion

Option 3 (Hybrid Architecture) is the only candidate that satisfies all safety, performance, and aesthetic requirements of COD-29 while maintaining minimal maintenance risk. Development will proceed strictly within `.worktrees/cod-29` under the gated sequence detailed above.
