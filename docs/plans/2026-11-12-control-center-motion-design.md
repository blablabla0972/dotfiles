# Control center motion

## Approved direction

The user selected option 1: stable content behind a downward reveal, approximately
300 ms opening and a shorter close. Preserve the final 760 × 440 layout, palette,
transparent backdrop, tabs and Wi-Fi/Bluetooth sidecars. No spring, staggered cards,
new dependencies or unrelated control-center repairs.

## Cause and scope

`Dashboard.qml` currently gives the content the shape's animated width and height.
The nested three-column layout therefore changes size throughout the animation.
Independent geometry, position and opacity animations also finish at different
times. The fixed close timer does not support reopening while closing, and the
pending open timer is not cancelled by dismissal.

## Motion

Use one reversible `revealProgress` animation: 300 ms open, 200 ms close. Derive
the background width/height and top offset from it. Disable the shared shape's
internal animations only for this Dashboard instance to avoid double easing.
Keep the content 760 × 440 inside one animated clipping viewport; derive its
small upward offset and fade from the same progress. Do not animate layout size.

Keep the surface visible until the actual reveal reaches zero. Cancel pending
opening on dismissal; reopening during closing reverses from the current value.
Retain the existing short initial mapping delay and sidecar animations.

## Verification and safety

Use a native offscreen Qt test with the actual Dashboard animation, timers and
IslandShape; stub hardware-backed tab bodies only. Check content dimensions
during opening/closing, fade/translation, final dimensions, interrupted closing,
early dismissal and sidecar integration. Run existing tests and the tracked-file
validator; distinguish existing failures from regressions.

Preview only Quickshell from an isolated worktree after installer dry-run. Check
live QML logs and `hyprctl configerrors`, and capture the open panel. Restore the
previous Quickshell checkout with its installer to roll back. Theme generation,
wallpaper ownership, runtime state and other components remain unchanged.
