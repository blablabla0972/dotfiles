# Carousel texture rendering

Use Qt's native [ShapePath.fillItem](https://doc.qt.io/qt-6/qml-qtquick-shapes-shapepath.html#fillItem-prop)
with the existing slanted path instead of a layered mask plus MultiEffect.
Keep an Image layer so Qt retains PreserveAspectCrop, transparency and HiDPI
handling; layers and fills remain disabled for inactive cards. Directly filling
with the unlayered Image was rejected because its texture coordinates changed
the crop. No custom shader, dependency or image-coordinate calculation was added.

Appearance constraints: retain geometry, borders, palette, thumbnail dimensions
and quality, smoothing, selection/input handlers and all animation durations.

Native measurement: Qt 6.12 RHI/OpenGL, Intel UHD/i915, 1920×1080 logical window,
the actual QML body/geometry, six cached wallpapers and 12 model rows. Five
alternating fresh processes, sampled after 900 ms; DRM clients deduplicated by id.

| Median | Before | After |
| --- | --- | --- |
| GPU resident buffers | 155.2 MiB | 137.0 MiB |
| Process RSS | 151.7 MiB | 158.3 MiB |

This saves 18.1 MiB of GPU buffers while increasing process RSS by 6.6 MiB;
these counters may overlap on integrated graphics and must not be added together.

Three alternating animation runs per version used identical 260 ms navigation requests,
unchanged 240 ms motion and a three-second measurement window. Each produced
310 frameSwapped signals. Median GPU engine time per frame fell from 1.436 to
1.099 ms (23.4%); CPU time per frame was 1.290 versus 1.419 ms, with overlapping
run ranges. These are isolated render measurements, not desktop FPS or battery
life claims.
An additional navigation run ended at 165,840 versus 141,040 KiB of GPU resident
buffers, confirming that the saving also persisted after repeated card resizing.

Verification:

- Real GPU captures at scale factors 1, 1.5 and 2, plus fractional path offsets
  1.25 and 3.5: retained crop, slanted frames, selection borders and colors.
  Images are visually comparable, not pixel-identical; full-capture normalized
  RMSE at rest was 0.00785, 0.00705 and 0.00723 respectively.
- Empty-source and transparent-image captures checked separately.
  Empty-source captures matched exactly; overlapping translucent color samples
  and the selected transparent center also matched.
- `python3 -m unittest discover -s tests -q`: 210 tests passed, no skips.
- Full Quickshell config loaded without QML errors; qmllint retained eight
  existing warnings, with no errors.
- Hyprland reported no configuration errors; Noctalia configuration validated.
- The session was locked with DPMS off, so captures used an independent native
  offscreen RHI window on the actual GPU; no unlocked desktop visual test occurred.

Other measured paths did not justify extra caches or rewrites: native palette
resolution and a warm thumbnail check each took about 19 ms. Generated colors,
theme transactions, wallpaper selection, live symlinks and private edits remain
outside this patch. Rollback restores the prior mask/MultiEffect block in both
main and the active Quickshell preview. The reviewed patch was applied to the
existing `.worktrees/rice-audit-agy-20261030` preview; its source matches the tested
candidate, and the original source was saved under `/tmp/dotfiles-texture-live-before.qml`.
