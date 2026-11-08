# Carousel initial-model optimization

Goal: reduce avoidable startup delay while retaining the existing appearance.
Approach: use Qt's existing Timer binding, with interval 0 only while the model
is empty and the current 80 ms debounce once populated; keep readiness/initial
wallpaper guards, model geometry, palette, image quality and animations intact.

Measurement: actual FolderListModel, model-building function and readiness
guards, Qt 6.12 offscreen, six filesystem entries, seven fresh processes per
version. Timing uses millisecond-resolution Date.now(), from data readiness to
model population; this is not total application startup, rendering latency or FPS.

| Ready-to-model time | Before | After |
| --- | --- | --- |
| Median | 81 ms | 0 ms |
| Range | 81–81 ms | 0–2 ms |
| Populated-model debounce | 80 ms | 80 ms |

Both versions produced the same 12 rows and selected image, with model/selection
SHA-256 `4d2f46430aa5cab04bd90f557c874d2f6d3f0450ec080d9aecb9a180d42b5f46`.

Implementation and acceptance:

- [x] Extend the existing native Qt test to require initial interval 0, later
  interval 80, one initial rebuild and one debounced refresh after repeated requests.
- [x] Change only the rebuild Timer's interval binding in runtime code.
- [x] Repeat the same native measurement; require identical model/selection digest.
- [x] Run native input tests, full suite and palette matrix.
- [x] Apply to the active preview without touching private edits or generated
  outputs; its QML source matches the tested candidate exactly.

Review focus: Qt interval changes during model clear/refill must not retrigger
the Timer; existing input focus, pointer behavior and selected wallpaper remain.

Verification:

- Existing native input test extended in place; failed with initial interval 80
  before the fix, passed with interval 0 afterwards. One initial build and one
  debounced refresh after three restart requests; no retrigger on clear/refill.
- `python3 -m unittest discover -s tests -q`: 210 tests passed, no skips.
- `python3 tests/check_palette_matrix.py --no-desktop`: all 24 cases passed.
- `qmllint`: no errors; eight existing warnings, diagnostic output unchanged.
- Both full Quickshell configurations loaded in the live Wayland session without
  QML runtime errors; the same host-portal registration warning appeared in both.
- Screenshots after entrance animation showed the same cards, selection and
  styling. In the 1920×410 ribbon crop at (0, 360), 154 of 787,200 RGB8 pixels
  differed, each by at most one level out of 255; this is a single steady-state
  comparison, not a frame-by-frame animation or multi-monitor acceptance test.

No additional thumbnail or palette cache was introduced: this machine has six
wallpapers and an already-cached palette preview measured about 3.3 ms excluding
Python startup. That does not justify another persistent cache or helper rewrite.

Deployment: the existing Quickshell symlink still points into
`.worktrees/rice-audit-agy-20261030/config/quickshell`; only the reviewed Timer
patch was applied there. Hyprland reported no config errors and Noctalia config
validation passed. Rollback is the inverse Timer change in main and that preview;
theme generation and transaction ownership are unchanged.
