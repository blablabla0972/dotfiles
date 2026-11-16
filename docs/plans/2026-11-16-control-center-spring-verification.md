# Balanced spring verification — 2026-11-16

## Result and scope

The active `~/.config/quickshell` link points to the candidate worktree. The
existing rice instance was soft-reloaded, not replaced with a second shell.

The changes cover native menu spring/reopen handling, connectivity drawers,
Island retraction and layer/mask bounds on short screens. No dependencies,
generated theme outputs or services changed.

## Automated evidence

- Isolated baseline: 412 tests, 107.157 s, OK; no skips.
- New native test red: three meaningful assertion failures for missing spring
  overshoot, missing contraction and ignored mid-exit reopening.
- New native test green: five tests, 5.424 s, OK. Actual Qt Controls menu:
  bounded overshoot, scale/opacity settlement, fixed content dimensions,
  mid-exit request retained without immediate scale reset, early/immediate
  dismissal, focus release, Escape and Return selection.
- Final full suite after the Island retract correction:
  `python3 -m unittest discover -s tests -q` — 418 tests, OK, no skips.
- `python3 tests/validate.py` and `git diff --check` — exit 0.

## Live evidence

- Installer dry-run reviewed; only `quickshell` installed with `--no-state`.
- Reload log: `Configuration Loaded`; health: `status=ok screens=1 mode=dark`.
- New log delta has only five pre-existing IpcHandler `Signal detected`
  warnings, no other QML warnings/errors. `hyprctl configerrors` is empty,
  exit 0.
- Recorded 307 real Wayland screenshots over 11.107 s on eDP-1, 1920×1080,
  scale 1. This sampling rate is not the compositor's 144 Hz render rate.
  Inspected settled Home, Wi-Fi, Bluetooth, Hotspot, reopened and closed frames,
  plus the opening contact sheet. No synthetic mouse/keyboard or service toggle
  was sent to the desktop. The dashboard was dismissed after checks; the final
  island layer is back to 46 px (media pill), not fullscreen.
- Island retraction was checked live: 6 px resting gap, 18 px expanded gap,
  complete visible body during closing, and bounded placement on a 640×360 screen.
- DND/night-light/awake/alert state unchanged. The existing `lastSummary`
  scalar resets on reload because `restoreNotificationHistory()` restores only
  the entry list; this unrelated behavior was not changed. The actual Alerts
  screenshot confirms all four original notification entries remain present.

Live captures, logs and installer backups remain local and are excluded from Git.

## Limits and rollback

Qt Menu's own visibility guard ignores `open()` during exit. `requestOpen()`
waits for native `closed` cleanup and defers reopening one event-loop turn.
Thus the small action menu finishes its 140 ms exit, rather than reversing a
physical spring immediately; the main pill/drawers do reverse mid-flight.
The action menu was tested under native offscreen Qt, not on the live Wi-Fi
list: the current adapter is occupied by the existing hotspot and exposes no
network rows. No physical input, multi-monitor, device operations, frame-time
benchmark or pixel-identical iOS/ColorOS acceptance is claimed.

To rollback the preview, run `install.sh --no-state quickshell` from the
original checkout and reload the rice shell. Both worktrees are retained.
Wallpaper generation and rollback ownership are untouched.
