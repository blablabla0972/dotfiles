# DESIGN SPECIFICATION: QUICKSHELL DYNAMIC ISLAND & CONTROL CENTER REDESIGN

**Date**: 2026-11-12  
**Author**: Lead Engineer (Quickshell / Qt Quick Architecture)  
**Target Repository**: `/home/admin/Projects/dotfiles/.worktrees/quickshell` (Branch: `quickshell`)  
**Input Reference Repositories**:
- `mavxa/DynamicGlacier` (MIT)
- `lunanoir21/quickshell-dynamic-island` (MIT)
- `Brainitech/Brain_Shell` (AGPLv3 — Clean-Room Rule Enforced)
- `caelestia-dots/shell` (GPLv3 — Clean-Room Rule Enforced)
- `andreumassanet/impasto` (GPLv3 — Clean-Room Rule Enforced)
- `amanhex/Ukishima` (MIT)
- `selvarn/NotchShell` (No License / All Rights Reserved — Clean-Room Rule Enforced)
- `fedyaqq34356/hyprdots` (GPLv3 — Clean-Room Rule Enforced)

---

## 1. Intent & Problem Statement

The Quickshell desktop environment on CachyOS/Hyprland currently features functional core components: a top bar, a Dynamic Island overlay, an application launcher, and a multi-tab control center. However, visual and interaction audit reveals:
1. **Geometric Collision & Seams**: In `06_island_volume_osd.png`, the top bar's `centerIsland` and the overlay `Island.qml` volume OSD collide at the top bezel. In `IslandShape.qml`, anti-corner ears lack outer strokes while the inner pill draws vertical border lines, producing visible vertical seams.
2. **Whitespace Imbalance**: `QuickSettings.qml` has a 75px+ empty gap between sliders and toggles (`02_control_center_home.png`). `System.qml` has 4 giant cards with massive empty centers (`03_control_center_system.png`). `Config.qml` wastes over 50% of card height on empty spacers.
3. **Accent Overuse**: Saturated gold accent (`#E4C36C`) dominates borders, text, tiles, and headers without a semantic hierarchy.
4. **Micro-Typography & Hardcoded Data**: Pervasive 10px micro-text degrades readability. `CalendarCard.qml` has a hardcoded 28-day grid that always starts on Monday. `System.qml` has hardcoded host/kernel strings.
5. **Background Process Leak**: `System.qml` runs a 2-second timer continuously executing `python3 telemetry.py` in the background even when Control Center is closed.

**Goal**: Elevate visual personality, geometry, animations, and layout density to match the high-end polish of **DynamicGlacier** and **Brain_Shell**, while maintaining zero background resource leaks, preserving all native services, and keeping 100% test pass rate.

---

## 2. License Audit & Clean-Room Rules

| Repository | License | Status | Restriction |
|---|---|---|---|
| `DynamicGlacier` | MIT | Permissive | Algorithms and reference concepts allowed |
| `quickshell-dynamic-island` | MIT | Permissive | Reference code allowed |
| `k4`, `Ukishima` | MIT | Permissive | Reference code allowed |
| `Brain_Shell` | AGPLv3 | **Strong Copyleft** | **ZERO CODE COPYING**. Clean-room independent QML only. |
| `caelestia-dots/shell` | GPLv3 | **Strong Copyleft** | **ZERO CODE COPYING**. Clean-room independent QML only. |
| `impasto`, `hyprdots` | GPLv3 | **Strong Copyleft** | **ZERO CODE COPYING**. Clean-room independent QML only. |
| `NotchShell` | No License | **All Rights Reserved** | **ZERO CODE COPYING**. Clean-room independent QML only. |

**Clean-Room Enforcement**:
- All QML files, component architectures, JavaScript helpers, and animation curves are authored independently from first principles.
- Mathematical formulations (SVG path coordinates, Hermite smoothstep, cubic Bézier curves) are standard geometry.

---

## 3. Baseline Audit & Defect Breakdown

### Baseline Artifacts:
Captured in `/home/admin/.gemini/antigravity/brain/7c6c88a1-94f5-4901-b344-0f650cf7b43c/scratch/baseline_screens/`:
1. `01_bar_idle.png`: Floating segmented bar with center island.
2. `02_control_center_home.png`: Home dashboard showing empty vertical gap in QuickSettings and missing media seek bar.
3. `03_control_center_system.png`: 2x2 grid with massive blank spaces inside each card.
4. `04_control_center_config.png`: Half-empty Config cards with redundant height.
5. `05_launcher.png`: Search box missing placeholder text, harsh yellow selection bar.
6. `06_island_volume_osd.png`: Top bar center island and overlay Island colliding directly at top bezel.

---

## 4. Architectural Solutions & Component Specifications

### 4.1. Seamless Dynamic Island Geometry & Collision Resolution

#### A. Eliminating the Double-Widget Collision:
- In `Bar.qml`, `centerIsland` monitors `Island.qml` state.
- When an OSD (volume/brightness) or notification alert triggers on `Island.qml`, `centerIsland` in `Bar.qml` smoothly cross-fades out (`opacity: 0.0`), allowing `Island.qml` to cleanly occupy the center space without visual overlapping.
- When `Island.qml` dismisses, `centerIsland` fades back in (`opacity: 1.0`).

#### B. Anti-Corner Seam Elimination in `IslandShape.qml`:
- Current flaw: `pillBody` has `border.width: 1`, stroking left/right vertical borders that cut off the anti-corner ears.
- Fix:
  - Remove vertical border lines between pill body and anti-corners.
  - Draw the anti-corners with matching border stroke along the concave curve using `ShapePath`:
    ```qml
    // In IslandShape.qml:
    // pillBody:
    border.width: 0 // eliminates interior vertical seams
    
    // Bottom border and side borders drawn cleanly
    // antiCornerLeft & antiCornerRight stroke only the concave outer curve:
    ShapePath {
        fillColor: root.fillColor
        strokeColor: root.borderColor
        strokeWidth: 1
        startX: antiCornerLeft.width; startY: 0
        PathLine { x: antiCornerLeft.width; y: antiCornerLeft.height }
        PathCubic {
            x: 0; y: 0
            control1X: antiCornerLeft.width * 0.45; control1Y: antiCornerLeft.height * 0.95
            control2X: 0; control2Y: antiCornerLeft.height * 0.35
        }
    }
    ```
- Enforce strict radius budgeting: $R_{\text{ear}} + R_b \le H$ so concave and convex arcs never overlap.

#### C. Bezel Fusion:
- No stroke along the top screen edge ($y = 0$).
- Background color matches `#000000` or `Tokens.surface` to eliminate optical contrast with physical monitor bezel.

---

### 4.2. Control Center Redesign (Brain_Shell Inspired 3-Column Home)

#### Dimensions & Spacing:
- Total width: `760px` (or scaled to screen ratio).
- Card radius: `14px`.
- Inter-column gap: `10px`.
- Padding: `12px`.

#### A. Left Column (`210px`):
- **ProfileCard** (`130px` height):
  - Avatar: Circular image mask or user icon with status dot (`online`).
  - Username: Bold primary text (`$USER`).
  - Subtitle: `Hyprland · CachyOS Linux`.
  - Uptime badge: compact pill (`up 3h 15m`).
- **CalendarCard** (fills remaining vertical space ~`220px`):
  - Dynamic month header with `<` `>` navigation.
  - Real month matrix: calculates exact first weekday of current month and total days (28–31).
  - Out-of-month days: muted `0.25` opacity; Today cell: accent ring highlight.

#### B. Center Hero Column (`320px`):
- **ClockCard** (`110px` height):
  - Large digital clock (`40px`, bold `JetBrains Mono` with tabular digits `tnum: 1`).
  - Formatted date: `Wednesday, November 12, 2026`.
- **PlayerCard** (fills remaining vertical space ~`240px`):
  - **Full-card blurred artwork background**: `Image` with `fillMode: Image.PreserveAspectCrop` and `MultiEffect` or opacity mask.
  - **3-stop dark gradient overlay**: `0.35` -> `0.65` -> `0.90` alpha to ensure text and controls are 100% legible.
  - **Track metadata**: Track title (bold, elided) + Artist & Album.
  - **Interactive Seek Bar**: Track progress bar with elapsed and remaining timestamps.
  - **Playback controls**: Previous, Play/Pause (accent circle), Next.
  - **Artwork fallback**: When `image.status !== Image.Ready`, render a deep neutral gradient with a refined `󰎆` glyph.

#### C. Right Column (`210px`):
- **QuickSettings (`QuickSettings.qml`)**:
  - **Integrated Sliders (`SliderRow`)**:
    - Volume slider track (height 34px): Left icon (`󰕾`), active fill bar (`Tokens.accent`), right percentage (`75%`). Continuous drag enabled!
    - Brightness slider track (height 34px): Left icon (`󰃠`), active fill bar, right percentage.
  - **Compact 2-Column Toggle Grid**:
    - 6 toggle tiles: Wi-Fi, Bluetooth, Mute, DND, Night Light, Awake.
    - Tile height: `38px` (radius 10px).
    - Inactive state: subtle surface background, neutral border.
    - Active state: subtle accent tint background (`0.14` alpha), accent icon, clean primary text.
    - **Zero wasted vertical space**: No `Layout.fillHeight: true` empty gaps!

---

### 4.3. System Tab Redesign (Dense Hardware Telemetry)

- Eliminate giant empty 2x2 cards.
- **Top Summary Strip**: Hostname, kernel, and session uptime in a clean, elevated pill strip.
- **Compact Metric Cards**:
  1. **CPU Card**: Usage percentage, model name, and 20-point `Sparkline` (historical CPU load via `QtQuick.Shapes` `PathPolyline`).
  2. **RAM Card**: Used / Total GB, percentage, and memory pressure indicator.
  3. **Storage Card**: Root filesystem (/) used / total GB, filesystem type, and clean progress bar.
  4. **System Health / Session Card**: Live load average, thermal readout / battery status, and Wayland display info.
- All dynamic data populated from `dashboard/telemetry.py`.

---

### 4.4. Config Tab Redesign (Grouped Ergonomic Settings)

- Eliminate the 50% dead vertical space in both columns.
- **Appearance Group**:
  - Dark Mode / Light Mode pill toggle with instant feedback.
  - "Regenerate Palette from Wallpaper" action button with subtle accent highlight.
  - **Active Palette Swatches**: Expanded swatch row displaying Accent, Surface, Surface High, Text, Outline, and Danger with clean color labels.
- **Runtime Group**:
  - Quick action buttons: Reload Rice Shell, Reload Hyprland, Refresh Theme Tokens.
  - Compact height (`40px`), clear button hierarchy (accent outline on primary actions).
  - Clean session status footer.

---

### 4.5. Performance, Lazy Loading & Interaction Hardening

1. **Lazy Loading via `Loader` in `Dashboard.qml`**:
   - Replace eager instantiation with `Loader { active: dashboardWindow.visible; source: ... }`.
   - Halts all background telemetry polling and timer wakeups when Control Center is closed.
2. **Top Bar Input Mask (`mask: Region`)**:
   - Add exact `mask: Region` in `Bar.qml` combining `leftIsland`, `centerIsland`, and `rightIsland`.
   - Prevents pointer click trapping on transparent bar gaps.
3. **Continuous Drag on Sliders**:
   - Add `MouseArea` / `DragHandler` for smooth, continuous dragging on volume and brightness tracks.
4. **SceneGraph Batching**:
   - Remove redundant `clip: true` on non-scrolling items (`Island.qml`, `Launcher.qml`).
5. **Minute-Boundary Clock Timer**:
   - Align top bar clock timer to minute boundary, cutting wakeups by 98.3%.

---

## 5. Verification & Acceptance Criteria

- **Test Suite**: 238/238 existing tests pass with 0 regressions. New tests added for anti-corner continuity, lazy loader, and slider drag.
- **Visual Evidence**: Fresh before/after screenshots under same resolution, scale, and theme.
- **Performance**: Zero background Python processes when Control Center is closed; CPU < 1.5% at idle.
- **Interaction**: Rapid toggle stress test (Super+X, Super+Space) runs smoothly with zero visual stutter or stuck scrims.
