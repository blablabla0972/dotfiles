# Repository guidance for Codex

This is an installable CachyOS/Hyprland dotfiles snapshot. Read [README.md](README.md) for the machine overview and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) before changing files; it records verified commands, file ownership, and task completion checks.

## Layout and live files

- `config/` maps to `~/.config/<name>`; `root/` maps individual files there; `state/` maps app state under `~/.local/state`; `bin/` maps utilities to `~/.local/bin`.
- The configured desktop is Lua-based: `config/hypr/hyprland.lua` loads `config/hypr/config/*.lua`. Noctalia and the Quickshell wallpaper picker are separate programs.
- On this host, the 14 active components are symlinks into the `main` checkout. Editing one of those source files changes the live configuration immediately. Other repository files are snapshots until installed.
- `install.sh --dry-run` previews link changes; selected installs create backups under `~/.config/backups/`. Selecting `noctalia` or `--all` can also install `state/noctalia/settings.toml`; pass `--no-state` when preserving the host's runtime state.
- For configuration or behavior work, use an isolated Git worktree. `wt-prep.sh <new-worktree>` copies machine-specific `current_wallpaper` and GPU files and replaces those destinations there; use it only on a newly created worktree. Preview only the changed components and follow the documented rollback procedure.

## Ownership and constraints

- Generate theme outputs through `config/hypr/scripts/generate-theme.py`. Do not hand-edit `config/hypr/colors.conf`, `config/hypr/noctalia.lua`, `config/noctalia/palettes/matugen.json`, or `config/micro/colorschemes/adaptive.micro`.
- Noctalia writes `state/noctalia/settings.toml`; inspect and preserve existing user changes. `config/hypr/current_wallpaper`, GPU selections, input-method state, and cache files can be host-specific. Never stage unrelated `git status` entries.
- Preserve the dark default and original lock-screen clock layout unless the user requests otherwise. Keep the existing wallpaper transaction owner and rollback/acknowledgment behavior when changing theme generation.
- Check for a nearer `AGENTS.md` before editing within a subtree. Do not index CodeGraph yourself; when `.codegraph/` exists, use its available index before searching source for symbols.
- There is no root build system, package manifest, CI workflow, or configured linter/formatter/type checker. Use the verified commands in `docs/DEVELOPMENT.md`; do not invent tooling.

## Done when

- The requested files and affected behavior are identified, and the diff contains no unrelated user or generated-file changes.
- Relevant tests and checks pass; report skips, failures, and checks that could not run. For live desktop changes, verify the relevant native config and compositor errors when the session is available; do not describe an offline check as visual acceptance.
- Generated outputs, rollback ownership, and any remaining unknowns are documented. Report changed files and the exact verification performed.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
