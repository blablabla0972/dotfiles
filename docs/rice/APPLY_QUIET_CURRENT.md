# Quiet Current: finish the desktop rollout

Source is on `feat/quiet-current` in `/home/admin/Projects/dotfiles/.worktrees/quiet-current`.
The desktop now previews this worktree, after access permissions were opened and
the controller applied/verified the native UI. Main merge awaits visual acceptance.
The commands below remain available to repeat or roll back the pre-merge preview.

Run from a terminal in the current Hyprland session:

```bash
bash /home/admin/Projects/dotfiles/.worktrees/quiet-current/docs/rice/preview-quiet-current.sh --dry-run
bash /home/admin/Projects/dotfiles/.worktrees/quiet-current/docs/rice/preview-quiet-current.sh --apply
```

This switches only the fourteen theme/source targets listed by the dry run,
uses `--no-state`, preserves the current wallpaper and dark setting, and calls
the existing theme owner. All generated app targets follow the worktree before
generation. Unexpected real directories/other worktrees are preserved by refusal.
An apply error attempts to restore main's configuration. No packages, services,
lock authentication or C++ binaries are changed; no merge/push is performed.

Check `SUPER+SPACE` and `SUPER+W`: keyboard navigation, preview swatches,
acknowledged apply, Escape, notifications/OSD and ordinary focus. The command
stores the real result record, effective config and optional desktop screenshot
under `$XDG_STATE_HOME/quiet-current-validation` (default `~/.local/state`).
Do not publish screenshots containing personal windows. Actual panel pixels,
multimonitor/fractional-scale/input/media/screen-sharing and sustained performance
still require the corresponding live checks; the single 10s baseline is not a
performance acceptance result. Lock/light-mode previews remain excluded per
the user's earlier preference.

Before merge, while the original main is still the baseline, return to it with:

```bash
bash /home/admin/Projects/dotfiles/.worktrees/quiet-current/docs/rice/preview-quiet-current.sh --rollback
```

Close the carousel and let pending theme work finish before rolling back.
Native session state is not reinstalled. Rollback atomically restores only the
validated component symlinks; main's old installer would select unrelated prompt/bin
targets by default and does not support `--no-state`. This pre-merge helper refuses
to run after main advances, so later user changes require a fresh inspection.
Original installer backups and transaction snapshots are retained by their owners.

After visual acceptance, explicitly approve the local merge. The controller must
recheck main's user changes, merge the verified branch, install from main with
`--no-state`, reload and inspect configerrors/effective config again. Keep the
worktree and backups until acceptance is complete.
