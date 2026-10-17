# Adaptive rice execution state

Plan: docs/rice/PLAN.md
Baseline: 72cc31145dd5e2f17935cb049ac578cca4cd54b0
Branch: rice-adaptive-polish
Worktree: /home/admin/Projects/dotfiles/.worktrees/adaptive-polish

- Task 1: complete — isolated worktree and selected live application baseline.
- Task 2: complete — serialized mode hook, toolkit preferences, mode-aware deduplication and rollback regression fixes.
- Task 3: complete — floating grouped bar, adaptive borders/surfaces, launcher and terminals.
- Task 4: complete — see VALIDATION.md for tests, live checks and measurement limits.
- Task 5: complete — implementation bddc83ad27ac60d93cf9e8c295b15de03bf744f2 merged into main, installed from main and pushed to origin/main; remote hash verified. Delivery notes are committed afterward.

User corrections: remain in dark mode and retain the original lock hours/minutes layout without the clock card. No more lock or light-mode previews.

Ruling: use rice-adaptive-polish because existing branch rice prevents rice/adaptive-polish. Preserve existing unrelated worktree rice.
Ruling: restore the user's original neutral lock text; Matugen still controls its existing check/error accents.
Environment: full access now allows live validation and GitHub. Earlier socket/DNS/tool-approval restrictions were resolved.
Review: two important findings reproduced and fixed; 10 transaction tests pass.

Final state: live configuration points to /home/admin/Projects/dotfiles on main; original wallpaper and workspace restored, mode dark, original lock layout retained. GitHub: blablabla0972/dotfiles.

Glass follow-up: bar 82% opacity, launcher 86.7% opacity plus blur; colors remain Matugen-derived. Twelve palette cases and live launcher preview verified; dark mode and original lock preserved.

Default-launcher correction: SUPER+SPACE invokes Noctalia, not Rofi. Set Noctalia shell.panel.transparency_mode to its supported glass mode; this shared option also styles its other popups. Preserve dark mode, Matugen palette and original lock.

Terminal glass: Kitty and Alacritty background opacity .82; Kitty dynamic_background_opacity enabled for future live adjustments. Existing Kitty processes need a new terminal process to adopt opacity.

Rofi removed on user request: package uninstalled; launcher configs, Matugen target, thumbnail generation and layer rule removed. Noctalia remains the SUPER+SPACE launcher.
