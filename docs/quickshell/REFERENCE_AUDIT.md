# Architectural & Provenance Inspection Report: Reference Repositories

**Location**: `/home/admin/.gemini/antigravity/brain/7c6c88a1-94f5-4901-b344-0f650cf7b43c/scratch/refs`  
**Host Quickshell Version**: `Quickshell 0.3.2 (Arch Linux)`  
**Date**: 2026-11-12

---

## 1. Reference Repositories Matrix

| Repository | Commit SHA | License | Usable Files & Ideas | API Differences with Quickshell 0.3.2 | Architectural Patterns to Avoid |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Brainitech/Brain_Shell** | `4b647c34663bf952e353809e7de1ccbc401861c2` | AGPL-3.0 | • `src/services/home/DashHome.qml`: 3-column dashboard (Profile+Calendar, Clock+Media, Brightness+Quick Toggles)<br>• `src/popups/Dashboard.qml`: Pill tabs with parallax `SlidePage` transitions<br>• `src/components/SurfaceShape.qml`: Convex/concave screen-frame cutouts via `ShapePath` (`OddEvenFill`) | Uses `PanelWindow` spanning fullscreen with `exclusionMode: Ignore` and `Region` masking; shells out to bash (`nmcli`, `bluetoothctl`, `rfkill`, `pgrep`) rather than native Quickshell services. | Fullscreen transparent window with giant `OddEvenFill` frame causes severe GPU overdraw; spawns heavy bash subprocesses on 5s polling loops (even for `$HOME`). |
| **mavxa/DynamicGlacier** | `9c22df9ae21fd8a022e9553a011716257cf741a8` | MIT | • `quickshell/modules/dynamicGlacier/IslandSurface.qml`: Smooth concave bezel anti-corners (`PathCubic`)<br>• `DynamicGlacier.qml`: Direct use of native `Mpris`, `Pipewire`, `UPower`, and `Bluetooth`<br>• Native PipeWire link group stream topology inspection for privacy indicator dot | Correctly leverages native `Quickshell.Services` (`Mpris`, `Pipewire`, `UPower`, `Bluetooth`), `IpcHandler`, and `WlrLayershell.keyboardFocus: OnDemand`. | Dynamic `screen: root.focusedScreen()` on a single `PanelWindow` causes Wayland surface re-instantiation / flickering across monitor switches instead of using `Variants`. |
| **lunanoir21/quickshell-dynamic-island** | `4fb44c6438cdf3b3969d052e3c5d687fa07c5d3e` | MIT | • `DynamicIslandHost.qml`: Idiomatic multi-monitor window hosting via `Variants`<br>• `DynamicIsland.qml`: Strict alert priority model (Calls > Alarms/Timers > Toasts; DND punch-through for calls/alarms)<br>• IPC coordinate telemetry (`islandWidth`, `islandHeight`) for screenshot tools | Uses `IpcHandler`, but relies heavily on an external monolithic bash daemon (`backend.sh`) streaming JSON over `SplitParser`. | Monolithic 6,000-line single QML file; external bash child process (`backend.sh`) polling sysfs/D-Bus when native Quickshell 0.3.2 C++ services already provide this reactively. |
| **selvarn/NotchShell** | `9de88d7752b1b574e7a45ebb8dfc0f97aa0ac71e` | **NONE (All Rights Reserved)** | • `components/Notch.qml`: Physics-based drag-down gesture (`DragHandler` with velocity flick) & hover latch strip<br>• `components/NotchShape.qml`: Mathematically budgeted radii preventing path foldover; attached ear vs detached floating sheet crossfade | Pure QML layout; custom mathematical easing functions (`Config.overshoot`, `Config.mix`, `Config.smooth`). | Completely unlicensed codebase; direct copy-paste would constitute strict copyright infringement. Must be clean-room reimplemented. |
| **amanhex/Ukishima** | `d04d8e1575bf0f7fc42922df7dca1ee9ac3a4027` | MIT | • `shell.qml` & `surfaces/*`: Single persistent morphing capsule hosting all sub-surfaces (Mixer, Calendar, Launcher, etc.)<br>• Two-layer window model: invisible zero-content `reserve` (`ExclusionMode.Normal`) + full-screen input-masked `overlay` (`ExclusionMode.Ignore`) | Advanced usage of `Variants`, `IdleInhibitor`, `IpcHandler`, and dynamic `mask: Region` switching between rest pill and full modal scrim. | Complex nested state machines in JS files; high memory footprint if surfaces remain loaded (mitigated by custom `unloadClosed()` timer). |
| **enhaoswen/Tide-island** | `fbc165d7c4e823ab6f6946f472a87e0ffe79acbf` | GPL-3.0 | • `shell.qml`: IPC routing targeted strictly to active/focused monitor window (`forFocusedWindow`)<br>• Multi-page swipe gesture navigation (`swipeLeft`/`swipeRight`) | Hybrid C++ plugin (`IslandBackend`) + QML frontend; exposes multiple specialized `IpcHandler` targets (`overview`, `island`, `tide`, `weather`, `calendar`). | Hard dependency on custom compiled C++ shared library plugins and CMake build steps; unsuitable for portable zero-compilation user dotfiles. |
| **k4ditano/k4** | `5b1406c2267440c97c4c9986a9fa19c7424094c0` | MIT | • `api/K4/Plugin.qml`: Decoupled plugin contract with strict numeric priorities, `transitorio` preemption flag, persistent background services list, and lazy `view: Component`<br>• Tri-state keyboard focus semantics (`grabKeyboard`, `tecladoOpcional`, `tecladoAlPasar`) | Elegant plugin abstraction over Quickshell IPC, Wayland focus layers, and dynamic surface resizing. | Overly granular folder structure (dozens of tiny micro-plugins); Spanish-only naming convention in core APIs (`habilitado`, `foco`, `fichero`). |
| **caelestia-dots/shell** | `fd630ffedd45eb31817e9a1726a0f567e79f65e2` | GPL-3.0 | • `modules/dashboard/Content.qml`: `pragma ComponentBehavior: Bound`, `ScriptModel` tabs, horizontal `Flickable`, viewport-based lazy loader binding<br>• `modules/bar/Bar.qml`: Vertical bar with `Repeater` + `DelegateChooser`, scroll wheel actions for volume/brightness, hover hit-testing `checkPopout(y)` | High-performance QML: utilizes Qt 6.5+ `ComponentBehavior: Bound` and declarative `DelegateChooser`. | Tight coupling with custom C++ backend modules (`Caelestia`, `Caelestia.Config`) and bespoke CSS token generation engine. |

---

## 2. License & Provenance Policy: Strict Clean-Room Rules

To ensure this dotfiles repository remains free of copyleft viral contamination and copyright infringement:
1. **Zero Verbatim Code Copying**: No code blocks from `Brainitech/Brain_Shell` (AGPL-3.0), `enhaoswen/Tide-island` (GPL-3.0), `caelestia-dots/shell` (GPL-3.0), or `selvarn/NotchShell` (unlicensed) may be copied or distributed in this repository.
2. **Mathematical & Architectural Clean-Room Derivation**:
   - Concave anti-corners are derived from independent cubic Bézier curves (`PathCubic`) matching monitor bezel radii.
   - Dynamic Island state machine is written independently in pure declarative QML and JavaScript.
   - Control Center is designed as a clean-room responsive 3-column QML layout using existing Quiet Current tokens (`adaptive-theme.json`).
3. **Pure Native API Usage**:
   - Utilize native `Quickshell.Services` (`Pipewire`, `Mpris`, `UPower`, `SystemTray`) and `Quickshell.Hyprland` exclusively.
   - Avoid ad-hoc background polling scripts and custom compiled C++ plugins.
