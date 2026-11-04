# Desktop audit fixes

Scope: the supplied audit of `70df281` and the request to fix all remaining items.
Work in `.worktrees/audit-confirmed-fixes`, preserving unrelated live changes.

1. Float Dolphin, Ark and pavucontrol explicitly; keep persistent sizes. Use
   Noctalia as the sole idle/locker owner, preserving the 180/300/360/1800-second
   behavior and brightness restore; leave conflicting hypridle disabled.
2. Keep Hermes opt-in and skip missing installations. Resolve swww from either
   the local or system installation without a new launcher/dependency.
3. Start thumbnail generation with the carousel. Stream ready cache keys so
   cards use thumbnails as each becomes available, with placeholders while
   waiting and bounded original-image fallback only after generation fails.
   Preserve caching, atomic writes, transaction acknowledgments and rollback.
4. Reduce blur passes to one. Match transition FPS to the highest active monitor
   refresh, capped at the backend's limit, with a conservative offline fallback.
5. Remove GTK4's dependency on absolute theme-asset symlinks and Brave's forced
   dark mode. Keep semantic theme generation as the sole owner of theme output.
6. Stop tracking generated Graphify artifacts while retaining all local files.
7. Run regression tests, shell/Lua/native QML checks and the palette matrix;
   review standards and audit coverage separately. Record unavailable live/GPU
   verification explicitly rather than equating offline checks with acceptance.

Interfaces: the thumbnail producer emits newline-separated MD5 cache keys;
the QML consumer accepts only those keys and waits for stream completion before
enabling fallback. FPS discovery must never prevent a wallpaper transaction.
Portable GTK overrides import the same generated `noctalia.css` as `gtk.css`.

Completion evidence (2026-11-04):

- Utility app IDs float in live native test windows; compositor config has no errors.
- Native Noctalia config validates/reloads, all four timers are enabled, and the
  controlled dim/resume test restores brightness exactly; hypridle stays disabled.
  Startup hook and Super+L share the native locker; layouts are unchanged.
- Missing Hermes skips with zero restarts; swww is active and actual systemd
  executable lookup succeeds. No failed user services remain.
- Live carousel renders without errors; isolated streaming/fallback/click checks,
  164 unittests and 24 palette cases pass. Original preview changes are retained.
- Live monitor is 144.005 Hz and transition FPS 144; final blur passes 1. Three
  Control Center trials per setting after warmup give median compositor render
  busy 24.208% at 2 passes versus 22.508% at 1, a workload-specific result.
- GTK4 imports parse; Brave no longer forces dark mode on its next startup.
  Graphify artifacts remain on disk, outside Git tracking.
- Main and active Noctalia/Quickshell previews are patched; publication to
  `origin/main` was requested on 2026-11-04. Unrelated preview work stays local.

Native source verification found that the initial hypridle autostart would
conflict with Noctalia's ScreenSaver/logind ownership and lose D-Bus inhibitors.
The final native idle configuration replaces that attempt, with no second daemon.
The native started hook runs after IPC initialization and also runs on shell
restart; config reload never executes it. Actual lock/suspend were not forced
while the user was working; their native actions and logind capability were checked.
Existing qmllint PathAttribute warnings and optional-executable verifier warnings
are documented in DEVELOPMENT.md; they are not hidden as clean lint passes.
