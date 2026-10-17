# Adaptive rice — approved implementation plan

Goal: a floating grouped bar and a coherent, restrained desktop that follows every Matugen wallpaper palette in dark and light mode.

## Design contract
- Noctalia: top bar, margins 10/14, radius 16, outline 1, opacity .92; launcher/clock left, workspaces center, status right. Preserve current UI scales. Adwaita Sans for the UI; no permanent error accent on the session button.
- Hyprland: gaps 5/10, radius 14, border 2, opaque application surfaces, palette-driven borders, subtle shadows/blur, short animations without overshoot.
- Rofi: wallpaper side panel 30%, results 70%, width min(70%,900px), height at most 75%; semantic foreground/background pairs.
- Lock: retain the original borderless stacked hours/minutes, dim wallpaper and password pill; preserve original neutral text and Matugen check/error accents. User explicitly rejected the clock card during live preview. Authentication is unchanged.
- Kitty/Alacritty: font 12, padding 14, opacity .96, no cursor trail. Preserve native theme includes. GTK/Qt use existing native templates.
- Wallpaper source and Matugen palette remain unchanged; default mode remains dark.

## Tasks
1. Record clean baseline, synchronize selected application snapshots, use an isolated worktree.
2. Test and implement a serialized --theme-mode-changed path: regenerate auxiliary Matugen outputs, apply native templates, reload, snapshot/rollback without changing wallpaper/mode. Include mode in wallpaper transaction deduplication.
3. Apply geometry, typography and semantic colors across existing components; validate each group.
4. Exercise six wallpaper classes in both modes, foreground contrast >=4.5:1, repeat/mode switching, invalid input/rollback, parser checks, then live previews and idle/interaction checks.
5. Commit reviewed changes, merge main, reinstall changed components, reload and push origin/main. Verify remote equals local. Preserve visibility; no force push or secrets.

## Delivery constraints
- Existing branch rice prevents the originally suggested rice/adaptive-polish ref. Use rice-adaptive-polish in .worktrees/adaptive-polish.
- Generated files must be rendered, never hand-edited. Baseline 72cc31145dd5e2f17935cb049ac578cca4cd54b0.
- Roll back with snapshots and tracked revert commits, never destructive reset.
