# COD-29 Foundation Test Report: Top-Edge Workspace Drag for Rice Shell

- **Document**: `docs/cod-29/foundation-test-report.md`
- **Worktree**: `/home/admin/Projects/dotfiles/.worktrees/cod-29`
- **Branch**: `feat/cod-29-top-edge-workspace-drag`
- **Date**: 2026-11-22
- **Author**: Teamwork Engineering (COD-29 Technical Systems & QA Specialist)
- **Status**: **VERIFIED & PASSED (Milestones 1–4 Gates Cleared)**
- **Linear Issue**: [COD-29: Top-edge Workspace Drag (Hymission-inspired)](https://linear.app/codechinh/issue/COD-29/top-edge-workspace-drag-keo-cua-so-bang-super-len-mep-tren-dje-tha-vao)
- **Target Subsystem**: Hyprland 0.57.2 Native C++ Plugin & Quickshell Rice Shell Integration

---

## 1. Executive Summary & Verification Overview

This document constitutes the comprehensive verification and test report for the foundational implementation of **COD-29: Top-edge Workspace Drag for Rice Shell**. COD-29 introduces a spatial drag-and-drop gesture into Hyprland and Quickshell: when dragging a window via the global mouse move binding (`Super + Left Mouse Button`), hovering at the physical top display edge smoothly reveals a horizontal workspace strip, enabling atomic window transfers to target workspaces without stealing pointer grabs or disrupting keyboard workflows.

### 1.1 Architecture Decision Summary (Option 3: Hybrid Architecture)
As established and approved in `docs/cod-29/architecture-decision.md` (Milestone 1, commit `0567ff1`), the system adopts **Option 3: Hybrid Architecture**:
- **Native Hyprland C++ Plugin (`libcod29_top_edge_drag.so`)**: Acts as the single authoritative owner of gesture recognition, dwell timing, coordinate containment, atomic release interception, and compositor window transfers.
- **Quickshell Rice Shell Strip (`TopEdgeWorkspaceStrip.qml`)**: Serves strictly as a visual presentation layer driven via a local UNIX domain socket IPC (`cod29.sock`). Quickshell takes zero pointer grabs (`WlrKeyboardFocus.None`, non-exclusive layer-shell overlay) and dispatches no asynchronous window movements.
- **Single Owner Invariant**: The native state machine maintains complete lifecycle control, eliminating grab conflicts, race conditions, and compositor layout corruption.

### 1.2 Gate Clearance Across Milestones 1–4
The foundation was developed iteratively under strict multi-agent validation gates (Auditor, Reviewers, Challengers):
- **Milestone 1 (Phase A: Architecture & Isolation)**: Gate PASS (commit `0567ff1`). Evaluated 4 architecture options, rejected Hymission fork (Option 1) due to GPL contagion and ABI fragility; rejected pure QML (Option 4) due to lack of global cursor streaming and Wayland grab conflicts; accepted Option 3.
- **Milestone 2 (Phase B: Native Drag Spike & ABI Check)**: Gate PASS (commit `233a528`). Verified bit-for-bit ABI hash match (`11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947_aq_0.16_hu_0.14_hg_0.6_hc_0.1_hlg_0.6`), resolved all 4 critical dynamic ELF symbols, and formulated Hardening Rules H1, H2, H3.
- **Milestone 3 (Phase C: Pure C++ State Machine Core)**: Gate PASS (commit `9a5f341`). Built compositor-independent state machine with feature flag defaulting to OFF (`top_edge_drag_enabled = false`), verified 15/15 deterministic unit tests (L01–L15), and passed 20 boundary probes and 100,000-cycle chaos fuzzing.
- **Milestone 4 (Phase D: Conditional MVP Implementation & Remediation)**: Gate PASS (commit `324386c`). Built native plugin, hook adapter, IPC server, Quickshell strip, and integration suite IT01–IT13. Successfully cleared three adversarial review waves, resolving Defects C1 (Double Close), C2 (Immediate Disconnect Message Loss), C3 (Binary Safe Append), C4 (64KB Buffer Cap), and C5 (Concurrent StateMachine Thread-Safety) with zero ThreadSanitizer or AddressSanitizer findings.

### 1.3 Key Verification Metrics
| Suite | Binary / Target | Total Cases | Passed | Failed | Status |
|---|---|---|---|---|---|
| **Core Logic Unit Tests** | `top_edge_drag_logic_test` | 15 | 15 | 0 | **100% PASS** |
| **Native Spike & ABI Check** | `native_spike_check` | 5 checks / 4 symbols | 5 | 0 | **100% PASS** |
| **Integration & Concurrency** | `cod29_integration_test` | 13 | 13 | 0 | **100% PASS** |
| **Adversarial Defect Probes** | Remediation Waves 1–3 | 5 defects / 3 rules | 8 | 0 | **100% RESOLVED** |
| **Live Desktop Safety Audit** | Host Session Inspection | 5 criteria | 5 | 0 | **100% CLEAN** |

---

## 2. Core Logic & Deterministic Unit Tests (L01–L15)

The pure C++ state machine (`include/cod29/top_edge_drag_logic.hpp`, `src/cod29/top_edge_drag_logic.cpp`) operates independently of Wayland, OpenGL, or Hyprland headers. It implements an 8-state transition model:
$$\text{Idle} \longrightarrow \text{Dragging} \longrightarrow \text{EdgeArmed} \longrightarrow \text{StripOpen} \longleftrightarrow \text{HoverTarget} \longrightarrow \text{DropIntent} / \text{NativeReleaseOnly} \longrightarrow \text{Idle}$$

All 15 unit tests (`tools/cod29/top_edge_drag_logic_test.cpp`) execute deterministically without flaky timers or sleeps.

### 2.1 Test Specification and Results Table

| ID | Test Name & Description | Test Inputs & Sequence | Expected Behavior / State Transition | Actual Output & State | Result |
|---|---|---|---|---|---|
| **L01** | Feature flag OFF (Default OFF constraint) | `Config::enabled = false`<br>`onNativeDragBegin(101, Move, true, 1, 100)`<br>`onPointerMotion({500, 2}, mon, 150)`<br>`onNativeRelease(200)` | All events emit `Action::None`. State machine remains locked in `State::Idle`. Zero IPC actions dispatched. | `Action::None` on all inputs.<br>`State::Idle`. | **PASS** |
| **L02** | Normal move below edge | `Config::enabled = true`<br>`onNativeDragBegin(102, Move, true, 1, 100)`<br>`onPointerMotion({500, 200}, mon, 120)`<br>`onPointerMotion({800, 500}, mon, 160)`<br>`onNativeRelease(200)` | `DragBegin` transitions to `State::Dragging`. Motions below edge emit `Action::None`. Release emits `Action::NativeEnd` and transitions to `State::NativeReleaseOnly`. | `Action::None` during drag.<br>`Action::NativeEnd` on release.<br>`State::NativeReleaseOnly`. | **PASS** |
| **L03** | Pointer at Rice bar boundary (40px reserved area ignored) | `edgeTolerance = 4.0`<br>`onPointerMotion({500, 42.0}, 110)`<br>`onPointerMotion({500, 40.0}, 120)`<br>`onPointerMotion({500, 20.0}, 130)`<br>`onPointerMotion({500, 4.0}, 140)` | Motions at $y=42, 40, 20$ emit `Action::None` (remain `Dragging`). Edge arms only when $y \le \text{mon.y} + 4.0$, emitting `Action::ArmEdge` and transitioning to `State::EdgeArmed`. | $y=42, 40, 20 \to \text{None}$.<br>$y=4.0 \to \text{ArmEdge}$.<br>`State::EdgeArmed`. | **PASS** |
| **L04** | Pointer reaches edge + dwell satisfied | `dwellTimeMs = 80`<br>`onPointerMotion({500, 2.0}, 100)`<br>`onPointerMotion({505, 1.5}, 150)` ($50\text{ms} < 80\text{ms}$)<br>`onPointerMotion({510, 2.0}, 180)` ($80\text{ms} \ge 80\text{ms}$) | $t=100$: `ArmEdge`, `EdgeArmed`.<br>$t=150$: `None`, remains `EdgeArmed`.<br>$t=180$: `Action::ShowStrip` with `windowToken = 104`, transitioning to `State::StripOpen`. | $t=100 \to \text{ArmEdge}$.<br>$t=150 \to \text{None}$.<br>$t=180 \to \text{ShowStrip}$.<br>`State::StripOpen`. | **PASS** |
| **L05** | Fast flick edge disarm before dwell completion | `dwellTimeMs = 80`<br>`onPointerMotion({500, 1.0}, 100)`<br>`onPointerMotion({500, 50.0}, 140)` ($40\text{ms} < 80\text{ms}$)<br>`onPointerMotion({500, 250.0}, 200)` | $t=100$: `ArmEdge`.<br>$t=140$: retreats before dwell, emits `Action::DisarmEdge`, timestamp cleared, reverts to `State::Dragging`. `ShowStrip` never emitted. | `DisarmEdge` emitted.<br>`m_edgeArmedTimeMs = 0`.<br>`State::Dragging`. | **PASS** |
| **L06** | Exit via hysteresis and clean re-entry | `stripHeight = 140.0`, `exitHysteresis = 28.0` ($\text{threshold} = 168.0\text{px}$)<br>Strip open.<br>`onPointerMotion({500, 100.0}, 200)`<br>`onPointerMotion({500, 160.0}, 220)`<br>`onPointerMotion({500, 169.0}, 240)`<br>`onPointerMotion({500, 2.0}, 300)` | $y=100, 160$: inside strip/buffer, emits `None` (`StripOpen`).<br>$y=169 > 168$: emits `Action::HideStrip`, reverts to `Dragging`.<br>$y=2.0$: re-enters edge, emits `Action::ArmEdge` (`EdgeArmed`). | $y=160 \to \text{None}$.<br>$y=169 \to \text{HideStrip}$.<br>$y=2.0 \to \text{ArmEdge}$. | **PASS** |
| **L07** | Mode discrimination & threshold filtering | 1. `DragMode::Resize`<br>2. `thresholdReached = false`<br>3. `DragMode::Other`<br>4. `windowToken = 0` | All 4 invalid gesture conditions emit `Action::None`. State machine remains in `State::Idle`. | `Action::None` across all 4 sub-cases.<br>`State::Idle`. | **PASS** |
| **L08** | Hover over valid workspace cards | Strip open.<br>`onWorkspaceCardHover(2)`<br>`onWorkspaceCardHover(3)`<br>`onWorkspaceCardHover(3)` (duplicate)<br>`onWorkspaceCardLeave()` | Hover 2 emits `Action::TargetChanged(2)` (`HoverTarget`). Hover 3 emits `TargetChanged(3)`. Duplicate emits `None`. Leave emits `TargetChanged(-1)` (`StripOpen`). | Target transitions 2 $\to$ 3 $\to$ idempotent $\to$ -1 verified.<br>States match accurately. | **PASS** |
| **L09** | Release over different workspace | `sourceWorkspaceId = 1`<br>Hover target card 2.<br>`onNativeRelease(250)`<br>`onCleanup()` | Release commits `Action::PrepareDrop(targetWs = 2, windowToken = 109)`. State transitions to `DropIntent`. Cleanup resets state to `Idle` and clears tokens. | `PrepareDrop` emitted.<br>`targetWorkspaceId = 2`.<br>`State::DropIntent` $\to$ `Idle`. | **PASS** |
| **L10** | Release over same workspace (Strict NO-OP policy) | `sourceWorkspaceId = 1`<br>Hover target card 1 (`target == source`).<br>`onNativeRelease(250)` | Release emits `Action::NativeEnd` (strict NO-OP). `PrepareDrop` is **never** emitted. State transitions to `NativeReleaseOnly`. | `Action::NativeEnd` emitted.<br>Zero move action.<br>`State::NativeReleaseOnly`. | **PASS** |
| **L11** | Release outside cards (Whitespace release) | Strip open without active card hover.<br>`onNativeRelease(250)` | Release in whitespace emits `Action::NativeEnd`. No workspace transfer dispatched. Transitions to `State::NativeReleaseOnly`. | `Action::NativeEnd` emitted.<br>`State::NativeReleaseOnly`. | **PASS** |
| **L12** | Compositor cancel events | Cancel from `Dragging`, `EdgeArmed`, `StripOpen`, `HoverTarget` via `SessionLock`, `WindowUnmapped`, `MonitorRemoved`, `DragSuperseded`. Cancel while `Idle`. | Active states emit `Action::Reset` and transition cleanly to `State::Idle`. Cancel while `Idle` is safe no-op emitting `Action::None`. | `Action::Reset` emitted on active states.<br>`State::Idle` preserved. | **PASS** |
| **L13** | Logical output offset / negative origin | Monitor origin $(-1920, -1080, 1920, 1080)$.<br>Pointer at $y=0$ (bottom/center).<br>Pointer at $y=-1070$ ($10\text{px}$ below edge).<br>Pointer at $y=-1078$ ($2\text{px}$ from $\text{mon.y} = -1080$).<br>Dwell satisfied. | Top edge calculated relative to $\text{mon.y} = -1080.0$. $y=0, -1070$ emit `None`. $y=-1078$ emits `ArmEdge`. Dwell completion emits `ShowStrip`. | Relative top edge accurately detected at negative offset.<br>`ShowStrip` emitted. | **PASS** |
| **L14** | Multi-monitor coordinate containment | Left mon: $[0, 0, 1920, 1080]$.<br>Right mon: $[1920, 0, 2560, 1440]$.<br>Pointer at $(2500, 2)$ tested on Left then Right.<br>Pointer at $(500, 2)$ tested on Right then Left. | Pointer on right monitor is rejected by left monitor (no coordinate bleed), arms right monitor only. Pointer on left monitor is rejected by right monitor, arms left monitor only. | Strict containment verified.<br>Zero cross-monitor bleeding. | **PASS** |
| **L15** | Release during dwell or post-cleanup (Single commit) | 1. Release during dwell ($t=140 < 180$). Duplicate release before cleanup.<br>2. Release after cleanup.<br>3. Accidental duplicate release after `PrepareDrop`. | Release during dwell emits `NativeEnd` $\to$ `NativeReleaseOnly`. Subsequent duplicate releases emit `Action::None`. Double release after `PrepareDrop` is suppressed. | Exactly one commit guaranteed.<br>Zero duplicate releases. | **PASS** |

---

## 3. Native Spike & Runtime ABI Verification

The native spike check (`tools/cod29/native_spike_check.cpp`, compiled and executed as `build/native_spike_check`) validates Hyprland 0.57.2 ABI compatibility, hook feasibility, and symbol linkages without touching live compositor state.

### 3.1 Bit-for-Bit ABI Hash Identity
Hyprland uses a multi-component hash in `PluginAPI.hpp` (`__hyprland_api_get_client_hash()`) to enforce plugin compatibility:
$$\text{ABI Hash} = \text{GIT\_COMMIT\_HASH} + \text{"\_aq\_"} + \text{AQ} + \text{"\_hu\_"} + \text{HU} + \text{"\_hg\_"} + \text{HG} + \text{"\_hc\_"} + \text{HC} + \text{"\_hlg\_"} + \text{HLG}$$

Comparison between header definitions and runtime compositor (`hyprctl version -j`):

| Component | Header Macro / Source | Header Value | Patched Value (`stripPatch`) | Runtime (`hyprctl version -j`) | Match Verdict |
|---|---|---|---|---|---|
| **Git Commit Hash** | `GIT_COMMIT_HASH` (`version.h`) | `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947` | `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947` | `"commit": "11cbc6c5..."` | **IDENTICAL** |
| **Aquamarine** | `AQUAMARINE_VERSION` | `"0.16.0"` | `0.16` | `"buildAquamarine": "0.16.0"` | **IDENTICAL** |
| **Hyprutils** | `HYPRUTILS_VERSION` | `"0.14.3"` | `0.14` | `"buildHyprutils": "0.14.3"` | **IDENTICAL** |
| **Hyprgraphics** | `HYPRGRAPHICS_VERSION` | `"0.6.0"` | `0.6` | `"buildHyprgraphics": "0.6.0"` | **IDENTICAL** |
| **Hyprcursor** | `HYPRCURSOR_VERSION` | `"0.1.13"` | `0.1` | `"buildHyprcursor": "0.1.13"` | **IDENTICAL** |
| **Hyprlang** | `HYPRLANG_VERSION` | `"0.6.8"` | `0.6` | `"buildHyprlang": "0.6.8"` | **IDENTICAL** |

- **Compiled Client Hash**: `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947_aq_0.16_hu_0.14_hg_0.6_hc_0.1_hlg_0.6`
- **Runtime Compositor Hash**: `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947_aq_0.16_hu_0.14_hg_0.6_hc_0.1_hlg_0.6`
- **Verification Verdict**: **100% Bit-for-bit exact match**. Zero ABI version skew.

### 3.2 Dynamic Symbol Resolution (/usr/bin/Hyprland)
Parsed directly from the ELF `.dynsym` table of `/usr/bin/Hyprland` (16,202 total symbols):

| Symbol Name | Demangled Signature | ELF Address | Size | Binding | Type | Section |
|---|---|---|---|---|---|---|
| `createFunctionHook` | `HyprlandAPI::createFunctionHook(HANDLE, const void*, const void*)` | `0x007bef20` | 119 B | `STB_GLOBAL` | `STT_FUNC` | 11 (`.text`) |
| `dragEnd` | `Layout::Supplementary::CDragStateController::dragEnd()` | `0x006b4f80` | 3,735 B | `STB_GLOBAL` | `STT_FUNC` | 11 (`.text`) |
| `globalWindowController` | `Desktop::globalWindowController()` | `0x005340c0` | 234 B | `STB_GLOBAL` | `STT_FUNC` | 11 (`.text`) |
| `moveWindowToWorkspace` | `Desktop::CGlobalWindowController::moveWindowToWorkspace(SP<CWindow>, SP<CHLWorkspace>) const` | `0x00534930` | 4,944 B | `STB_GLOBAL` | `STT_FUNC` | 11 (`.text`) |

All four required symbols are present with `GLOBAL` linkage and executable function type, guaranteeing hook and dynamic dispatch viability.

### 3.3 Compile-Time Type Invariants & Hook Mechanics
1. **`CDragStateController::dragEnd()` Return Type**: Compile-time assertion verified `std::is_same_v<decltype(std::declval<Layout::Supplementary::CDragStateController>().dragEnd()), bool> == true`. The method returns a boolean indicating whether drag termination was successful.
2. **Gesture Mode Filtering**: `CDragStateController::mode()` yields `eMouseBindMode`. `MBIND_MOVE == 0` is accepted; `MBIND_RESIZE == 1` is strictly ignored.
3. **Passive Pointer Tracking**: Listening to `Event::bus()->m_events.input.mouse.move` (`CSignalT<Vector2D, SCallbackInfo&>`) without setting `info.cancelled = true` preserves compositor pointer grab inviolability.

---

## 4. Integration Test Suite & Hardening Verification (IT01–IT13)

The integration test harness (`tools/cod29/cod29_integration_test.cpp`, compiled as `build/cod29_integration_test`) tests the interactions between `DragHookAdapter`, `IpcServer`, `StateMachine`, and `MockCompositorDelegate` across live UNIX domain sockets and concurrent threads.

### 4.1 Test Specification and Results Table

| ID | Integration Test Description | Verification Target & Mechanics | Result |
|---|---|---|---|
| **IT01** | IPC Server Handshake & Lifecycle | Verifies socket creation, non-blocking bind, `STRIP_READY` client handshake, connected client tracking, clean shutdown, and socket unlinking (`unlink`). | **PASS** |
| **IT02** | Full End-to-End Drag & Atomic Drop | Full sequence: drag begin $\to$ top edge pointer motion $\to$ 85ms dwell $\to$ `SHOW_STRIP` IPC $\to$ `CARD_HOVER 2` $\to$ native `dragEnd` $\to$ atomic `moveWindowToWorkspace(0x1001, 2, follow=false)` $\to$ state machine reset to `Idle`. | **PASS** |
| **IT03** | Same-Workspace Drop (NO-OP Policy) | Drag window from WS 1, open strip, hover WS 1 card, release. Confirms `dragEnd` succeeds, `moveCalls.size() == 0` (zero moves dispatched), and state resets cleanly. | **PASS** |
| **IT04** | Fast Flick Edge Disarm | Reaches edge (arms), then retreats $>4\text{px}$ before 80ms dwell. Verifies `HIDE_STRIP` broadcast, state reverts to `Dragging`, strip never opened. | **PASS** |
| **IT05** | Strip Dismissal via Exit Hysteresis | Strip opened, cursor moves to $y=160$ (within $140+28=168\text{px}$ buffer $\to$ stays open), then retreats to $y=170 > 168\text{px}$. Verifies `HIDE_STRIP` broadcast and state reversion to `Dragging`. | **PASS** |
| **IT06** | Hardening Rule H1 (Exception Quarantine) | Injects simulated `std::runtime_error` inside `onPointerMotion` and `onDragEnd`. Verifies exception is quarantined without escaping `noexcept`, logged via delegate, counter incremented, state reset to `Idle`, and strip hidden. | **PASS** |
| **IT07** | Hardening Rule H2 (Pre-Release Window Capture) | Captures window token before calling `origDragEnd`. Simulates window unmapping/destruction during `origDragEnd` (`isWindowValid() == false`). Verifies drop move is safely aborted, preventing stale handle crashes. | **PASS** |
| **IT08** | Hardening Rule H3 (Aborted Release Reset) | Simulates compositor `origDragEnd` returning `false` (superseded/cancelled). Verifies state machine resets via `CancelReason::DragSuperseded`, `HIDE_STRIP` emitted, and `onDragEnd` returns `false`. | **PASS** |
| **IT09** | Mode Discrimination Filtering | Initiates drag with `DragMode::Resize` and unreached threshold. Verifies adapter discards event, state remains `Idle`, and zero IPC messages are sent. | **PASS** |
| **IT10** | Client Disconnect / Reconnect Resilience | IPC client abruptly disconnects while strip is active, reconnects with fresh socket FD, and resumes communication. Verifies zero socket leaks and uninterrupted server operation. | **PASS** |
| **IT11** | Immediate Disconnect Message Retention (Defect C2) | Client connects, sends `CARD_HOVER` commands, and immediately calls `close(fd)` without sleeping. Verifies server drains `POLLIN` before closing, retaining 100% of messages without loss. | **PASS** |
| **IT12** | Concurrent Broadcast & Disconnect Safety (Defect C1) | 4 client threads rapidly connect, send, and close FDs concurrently while a background thread continuously broadcasts events. Verifies zero double `close(fd)` errors (`EBADF`) and clean server state. | **PASS** |
| **IT13** | Concurrent IPC Updates & Motion Thread-Safety (Defect C5) | Rapid IPC card bounds registration and hover/leave events on worker thread concurrent with 2,000 rapid pointer motions and card queries on main thread. Verified 100% data-race free under ThreadSanitizer. | **PASS** |

---

## 5. Adversarial Stress & Vulnerability Resolution

During Milestone 4 validation waves, adversarial stress testing and concurrency probes identified 5 critical/high-severity defects and 3 mandatory hardening rules. All were remediated and verified.

### 5.1 Defect Forensic Analysis & Fix Verification

```
+----------------------------------------------------------------------------------------------------+
|                                   DEFECT REMEDIATION MATRIX                                        |
+----+-----------------------+----------+------------------------------------+-----------------------+
| ID | Vulnerability         | Severity | Root Cause                         | Resolution & Fix      |
+----+-----------------------+----------+------------------------------------+-----------------------+
| C1 | Double Close Race     | Critical | sendToAllClients & cleanupClient   | Mutex guard & find    |
|    | Condition             |          | both closed abruptly severed FDs   | check before close()  |
+----+-----------------------+----------+------------------------------------+-----------------------+
| C2 | Immediate Disconnect  | High     | POLLHUP/POLLERR checked before     | Process POLLIN first; |
|    | Message Loss          |          | POLLIN, dropping pending recv data | drain recv() to EOF   |
+----+-----------------------+----------+------------------------------------+-----------------------+
| C3 | Stream Desync on      | Medium   | operator+= on raw C-string         | Binary-safe append:   |
|    | Null / Control Bytes  |          | truncated at embedded \0 byte      | append(buf, n)        |
+----+-----------------------+----------+------------------------------------+-----------------------+
| C4 | Unbounded Client      | Medium   | Continuous newline-free input      | 64KB hard cap on      |
|    | Buffer DoS            |          | caused unbounded memory growth     | incoming client buffer|
+----+-----------------------+----------+------------------------------------+-----------------------+
| C5 | StateMachine Data     | Critical | IpcServer thread mutated sm while  | Synchronize sm access |
|    | Race / SIGSEGV        |          | main thread ran onPointerMotion    | via m_stateMutex      |
+----+-----------------------+----------+------------------------------------+-----------------------+
```

#### Defect C1 (Double Close Race Condition — Critical)
- **Vulnerability**: When an IPC client disconnected abruptly, `sendToAllClients()` detected `EPIPE`/`ECONNRESET` and closed the FD. Simultaneously, `serverLoop()` or `cleanupClient()` encountered `POLLHUP` and closed the same FD. In a multithreaded Wayland compositor, double `close()` is dangerous: if the FD has been recycled by another subsystem (e.g., an unrelated Wayland client socket or file descriptor), `close(fd)` accidentally closes an innocent resource, leading to silent I/O failure or crashes.
- **Root Cause**: Lack of membership verification prior to invoking `close(clientFd)` in `cleanupClient()`.
- **Remediation**: In `src/cod29/ipc_server.cpp:161-170`, `cleanupClient()` locks `m_clientsMutex` and checks `std::find(m_clientFds.begin(), m_clientFds.end(), clientFd) != m_clientFds.end()`. If not found, the call safely returns without executing `close()`.
- **Verification**: Verified via test `IT12` running 100 rapid concurrent connect-disconnect cycles alongside active broadcasts. Zero `EBADF` or double-close occurrences.

#### Defect C2 (Immediate Disconnect Message Loss — High)
- **Vulnerability**: If a client sent a command (e.g. `CARD_HOVER 2\n`) and immediately called `close()`, `poll()` returned `POLLIN | POLLHUP`. `serverLoop()` previously evaluated `if (revents & (POLLHUP | POLLERR)) continue;` *before* `POLLIN`, immediately discarding the client before reading pending socket buffer data.
- **Root Cause**: Inverted priority between polling hangup status and reading available input data.
- **Remediation**: In `src/cod29/ipc_server.cpp:314-368`, `revents & POLLIN` is processed first. A `while (true)` loop drains the socket using `recv()` until `EAGAIN`/`EWOULDBLOCK` or EOF ($n=0$). Only after all pending lines are dispatched is the client marked for disconnection.
- **Verification**: Verified via test `IT11`, ensuring 100% of messages sent prior to immediate close are received and parsed.

#### Defect C3 (Binary Safe Append — Medium)
- **Vulnerability**: Incoming socket data was concatenated via `clientBuffers[fd] += buf;`. If any binary control byte or embedded `\0` was received, concatenation stopped at the null terminator, dropping remaining bytes and corrupting subsequent IPC commands.
- **Remediation**: Updated to binary-safe `clientBuffers[fd].append(buf, static_cast<size_t>(n));` in `src/cod29/ipc_server.cpp:332`.
- **Verification**: Tested with simulated fragmented payloads and null-containing streams; parser remains synchronized.

#### Defect C4 (Unbounded Buffer DoS — Medium)
- **Vulnerability**: An unauthenticated or misbehaving local client streaming data without newline characters could cause unbounded heap allocation in `clientBuffers[fd]`.
- **Remediation**: Implemented a hard buffer cap of 65,536 bytes (64KB) in `src/cod29/ipc_server.cpp:335-339`. If exceeded, the buffer is cleared and the client is immediately disconnected.
- **Verification**: Verified with oversized stream test; buffer drops immediately upon reaching 64KB.

#### Defect C5 (StateMachine Data Race & SIGSEGV — Critical)
- **Vulnerability**: `IpcServer::serverLoop()` executes on a background worker thread. When handling `REGISTER_BOUNDS`, `CARD_HOVER`, or `CARD_LEAVE`, it directly invoked methods on `StateMachine` (`setWorkspaceCards`, `onWorkspaceCardHover`, `onWorkspaceCardLeave`). Concurrently, Hyprland's main UI thread executed `onPointerMotion`, iterating over `m_workspaceCards` for geometric hit testing. Under ThreadSanitizer, this produced a severe data race and a fatal `heap-use-after-free` SIGSEGV at `top_edge_drag_logic.cpp:188` caused by vector reallocation during iteration.
- **Root Cause**: Unsynchronized concurrent access across thread boundaries to non-thread-safe `StateMachine` state.
- **Remediation**:
  1. Added `mutable std::mutex m_stateMutex;` to `DragHookAdapter` (`include/cod29/drag_hook_adapter.hpp:62`).
  2. Wrapped all IPC callbacks (`setHoverCallback`, `setLeaveCallback`, `setSetCardsCallback`) in `std::lock_guard<std::mutex> lock(m_stateMutex);`.
  3. Wrapped all compositor entry points (`onDragBegin`, `onPointerMotion`, `onDragEnd`, `onCancel`) and queries (`getState`, `getTargetWorkspaceId`, `getWorkspaceCards`, `setWorkspaceCards`) under `m_stateMutex`.
- **Verification**: Verified via test `IT13` executing 2,000 rapid compositor pointer motions concurrent with high-frequency bounds reallocations on the IPC thread. Clean execution under ThreadSanitizer (`-fsanitize=thread`) with zero race warnings.

### 5.2 Hardening Rules H1, H2, H3 Implementation
- **Hardening Rule H1 (Exception Quarantine)**:
  - Compositor crash prevention: In Hyprland, an uncaught C++ exception escaping a plugin hook terminates the entire compositor.
  - Implemented in `src/cod29/drag_hook_adapter.cpp:62-100` and `147-181`: all callbacks are marked `noexcept` and enclosed in nested `try ... catch (const std::exception& e)` and `catch (...)` blocks.
  - Exception quarantine safely increments `m_quarantinedExceptions`, attempts logging via `m_delegate->log()` (with its own inner try-catch to prevent logging OOM/exceptions from escaping), resets the state machine to `Idle`, and broadcasts `HIDE_STRIP`.
  - Verified by `IT06` with simulated exception injection.
- **Hardening Rule H2 (Pre-Release Window Reference Capture)**:
  - In Hyprland, a window may be unmapped or destroyed during the execution of `origDragEnd(thisptr)`.
  - Implemented in `src/cod29/drag_hook_adapter.cpp:106-133` and `src/cod29/plugin_entry.cpp:30-42`: window pointer is captured into `PHLWINDOWREF m_capturedWindowRef` *before* invoking `origDragEnd`. After `origDragEnd` completes, `m_delegate->isWindowValid()` checks `!m_capturedWindowRef.expired()`. If expired, workspace movement is cleanly skipped.
  - Verified by `IT07`.
- **Hardening Rule H3 (Aborted Release State Machine Reset)**:
  - If `origDragEnd(thisptr)` returns `false` (drag superseded by another compositor grab or aborted), the drop must not commit.
  - Implemented in `src/cod29/drag_hook_adapter.cpp:117-122`: if `!origResult`, `m_stateMachine.onCancel(CancelReason::DragSuperseded)` is immediately dispatched, dismissing the strip and resetting state to `Idle`.
  - Verified by `IT08`.

---

## 6. Safety, Non-Interference & Worktree Isolation Audit

A comprehensive live system audit was conducted to confirm total non-interference with the user's active desktop environment.

### 6.1 Audit Verification Checklist

| Audit Item | Verification Command | Expected Value | Observed Value | Status |
|---|---|---|---|---|
| **Live Plugin Isolation** | `hyprctl plugins list` | `no plugins loaded` | `no plugins loaded` | **PASS (CLEAN)** |
| **Compositor Uptime** | `ps -eo pid,etime,args \| grep Hyprland` | Continuous uptime ($> 3\text{h}$) | PID 964, running for $5\text{h } 31\text{m } 54\text{s}$ | **PASS (0 RESTARTS)** |
| **Live Config Protection** | `git status` in `/home/admin/Projects/dotfiles` | Dotfiles config unmutated by COD-29 | No COD-29 files in main repo | **PASS (CLEAN)** |
| **Worktree Branch Isolation**| `git branch --show-current` in worktree | `feat/cod-29-top-edge-workspace-drag` | `feat/cod-29-top-edge-workspace-drag` | **PASS (ISOLATED)** |
| **Keybinding Safety** | Audit `config/hypr/config/binds.lua` | `Super+Escape` and `Super+Tab` intact | No keybinding collision or synthesis | **PASS (INTACT)** |

### 6.2 Keybinding & Layer-Shell Non-Interference
- **`Super + Escape` Safety**: In Rice Shell, `Super + Escape` triggers interactive window kill mode (`cancelWindowSwitcher` with fallback to `hyprctl kill`). The COD-29 C++ state machine relies exclusively on internal state transitions (`CancelReason::SessionLock`, `WindowUnmapped`, etc.) and never synthesizes or injects synthetic `Escape` key events into Hyprland's input queue.
- **`Super + Tab` Window Switcher**: The window switcher operates independently. COD-29 only activates when an active native drag is initiated (`MBIND_MOVE` and threshold reached).
- **Quickshell Non-Interference**: `TopEdgeWorkspaceStrip.qml` uses `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None` and `exclusiveZone: 0`, ensuring that the top-edge workspace strip never steals keyboard focus or shifts desktop workareas.

---

## 7. Conclusion & Gate E Verdict

All technical criteria and safety constraints specified in `PROJECT.md`, `ORIGINAL_REQUEST.md`, and the linear issue COD-29 have been empirically verified and satisfied:
1. **Compositor-Independent Core**: 15/15 unit tests (L01–L15) pass deterministically.
2. **Native Spike Compatibility**: Exact ABI hash match and dynamic ELF symbol resolution confirmed.
3. **Integration & Concurrency Stability**: 13/13 integration tests (IT01–IT13) pass deterministically, ThreadSanitizer and AddressSanitizer clean.
4. **Adversarial Hardening**: All 5 identified defects (C1–C5) and 3 hardening rules (H1–H3) verified resolved.
5. **Zero-Impact Safety**: 0 live config changes, 0 live plugin reloads, 0 compositor restarts.

**Verdict: UNCONDITIONAL PASS. Gate E is cleared.** The COD-29 Foundation is ready for Batch 2 (Production UI & Full Rice Shell Integration).
