# Balanced Control Center spring motion

## Approved direction

The user selected **Lò xo cân bằng (Recommended)** on 2026-11-16: morph the
existing pill into Control Center, with one restrained spring overshoot. Apply
the same character to Wi-Fi, Bluetooth, Hotspot and small action menus. Closing
must be decisive, and interrupted motion must not jump. Preserve final layout,
semantic colors, services, input handling and notification history.

## Approach and scope

Native Qt Quick springs are preferred to a stronger, longer ColorOS bounce or
an OutBack imitation. The active `quickshell-professional-polish` checkout already
contains uncommitted native springs in `IslandShape.qml` and `Dashboard.qml`, plus
close-lifecycle, opacity and input fixes. Preserve these six source/test files
unchanged in the original checkout and copy them into a dedicated worktree.

The remaining gap is `dashboard/ActionMenu.qml`: its open transition still uses
OutCubic scaling and its close transition only fades. Replace its entry scale
animation with a native spring, anchor scaling at the menu's top-right, and add
a short scale contraction to its exit. Keep Qt Controls responsible for popup
visibility, focus and dismissal; add no custom lifecycle timer or dependency.

Native testing found that `QQuickMenu::setVisible()` has an additional visibility
guard, unlike `QQuickPopup::setVisible()`: reopening during exit is ignored.
The single Wi-Fi caller now uses `requestOpen()`, which remembers that request
and reopens on the native `closed` signal via `Qt.callLater` (after Qt restores
the popup properties). A request during completed-but-not-yet-stopped cleanup is
also deferred one event-loop turn. This small menu completes its 140 ms exit
before reopening; only the shared pill/drawer springs reverse immediately.

## Verification and ownership

An isolated native Qt test must observe actual popup scale/opacity, a restrained
overshoot, settled open/closed states and reopening during exit. Existing tests
cover fixed-size dashboard contents, connectivity menu springs, interrupted
main morphs, Escape, loader cleanup and release of the input mask.

Run the full unittest suite, tracked-file validator and diff check. Preview only
the Quickshell component after installer dry-run; reload through existing IPC,
check runtime diagnostics/compositor errors, and capture live opening/closing.
Do not synthesize desktop clicks, change networking, playback, theme outputs or
power state. Offscreen input tests are not physical mouse acceptance.

Baseline backup: `/tmp/opencode/control-center-spring-20261116/baseline/`.
Rollback by reinstalling only Quickshell from the previous
`quickshell-professional-polish` checkout and reloading the existing instance.
