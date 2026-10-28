# Quiet Current / Tidal Glass — native evidence and offline QA

2026-10-28. Scope: Phase 0 **native subset**, Phase 4 conservative config polish,
and offline palette QA. Live visual acceptance remains pending. Only this memo,
`config/noctalia/config.toml`, and `tests/check_palette_matrix.py` are owned here;
tokens/carousel/controller work belongs to other agents. No install, reload,
commit, fork edit, plugin, UI launch, live symlink/state or generated-file edit.
Temporary fixture/render files are removed with their isolated XDG directories.

## Revision and ownership evidence

| Item | Observed evidence |
|---|---|
| Quiet Current worktree HEAD | `6b832a8c0e85377b1617b2d474dd6db82df3a851`; initially clean; concurrent agents subsequently added their changes |
| Dotfiles main HEAD | Same HEAD; local untracked `config/fcitx5/conf/cached_layouts` observed, untouched |
| Native workspace root HEAD | `b98c8594ee4d1b3c8369296bcc21f53b2b90ad5f`; dirty `DELIVERY.md`, `SESSION_STATE.md`; untracked `validation/home-dashboard-review.png`, `worktrees/` |
| Wrapper | `/home/admin/.local/bin/noctalia` resolves to `/home/admin/noctalia-dashboard-redesign/run-noctalia.sh` |
| Selected binary | `/home/admin/noctalia-dashboard-redesign/build-v5.3-material-glass-native/noctalia` |
| Binary self-reported build pin | `noctalia v5.3.0 (v5.3.0-11-g5c1c69c8d69e-dirty)` — **not** root HEAD or proof of source/binary equivalence |
| Binary SHA-256 | `15fe1115b4ec26c72484432542004f65e6873b030324f932d6021f24c013ded2` |
| Wrapper assets/source | `/home/admin/noctalia-dashboard-redesign/worktrees/material-glass-5.3/assets`; owning checkout HEAD `0d320287a98c05519dc8255b2d7a1562d90f28e0`, clean |
| Live Noctalia config directory | `/home/admin/.config/noctalia` resolves to `/home/admin/Projects/dotfiles/config/noctalia`; selected worktree config is a regular, separate file |
| Runtime overrides | Resolved state file `/home/admin/Projects/dotfiles/state/noctalia/settings.toml` has no overrides for the three changed keys at inspection; no state written |

Root `AGENTS.md`, `SESSION_STATE.md`, `DELIVERY.md` describe older 5.2.1 work.
The wrapper and binary identify the current selection. Root CodeGraph was queried
first but returned `source/` symbols from the older layout; current nested checkout
has no `.codegraph/`, so targeted current source reads supply the evidence below.
Coverage is partial native source inspection, not a complete fork/upstream audit;
no external implementation was copied and no license/reuse claim is made.

## Supported configuration and lifecycle

Paths below are relative to the current native checkout at `0d320287`.

| Evidence | Consequence |
|---|---|
| `src/config/schema/config_schema.cpp:1377`, `src/config/config_types.cpp:192` | Panel enum supports `solid`, `soft`, `glass`; floating background/card alpha are respectively `1/1`, `.80/.88`, `.55/.65`. No numeric panel opacity key exists in this schema. |
| `src/shell/panel/panel_surface_style.h`, `src/shell/panel/panel_manager.cpp:2554` | Floating panel uses enum opacity; card alpha is propagated separately. Attached panels can inherit bar background opacity, so this model specifically covers floating panels. |
| `src/config/schema/config_schema.cpp:100`, `:293`, `:532` | OSD/notification `background_opacity` supported; control-center width/sidebar supported, no separate control-center alpha knob. |
| `src/shell/control_center/tabs/home_tab.cpp:154`, `src/shell/control_center/control_center_panel.cpp:130` | Home cards paint `Surface` with card opacity; sidebar paints `SurfaceVariant` with card opacity, above panel `Surface`. |
| `src/shell/notification/notification_toast.cpp:2451`, `:2803`; `src/shell/osd/osd_overlay.cpp:766` | Config alpha paints `Surface`; primary/secondary text uses semantic on-surface roles. OSD glyph/progress uses Primary, Error or OnSurfaceVariant; over-limit value uses Error. |
| `src/shell/bar/bar.cpp:1191` | Center section is independently centered, with optional widget anchoring; existing sole center widget remains workspaces. No invented `stable_center` key. |
| `src/shell/control_center/control_center_panel.cpp:54`, `:407`, `:444`, `:594` | Tab objects are constructed up front; active tab receives frame ticks; selection updates active flags; close cancels tab transition, deactivates tabs and calls their close handlers. This does not prove all hidden service work stops. |
| `src/shell/osd/osd_overlay.cpp:912` | Config hide timer starts close animation; deferred cleanup destroys OSD surfaces once all instances are idle. No new polling/render loop introduced. |
| `src/config/cli.cpp:328`, `src/config/config_validate.cpp:46` | Explicit-file validation avoids merged live config/state; normal merged configuration applies state overrides last. |

Current documentation fetched through Context7 from
[`/noctalia-dev/noctalia`](https://github.com/noctalia-dev/noctalia/blob/main/_autodocs/api-reference/cli.md)
confirms explicit-file validation. Pinned source and actual CLI behavior take
precedence: unknown keys produce **WARN with exit 0**, and numeric opacity `1.1`
was accepted silently (schema field readers clamp ranges). Malformed TOML exits 1.
The matrix therefore also rejects WARN/ERROR output; successful exit alone is
insufficient schema evidence. The selected config reports zero warnings/errors.

## Minimal material change

- `shell.panel.transparency_mode`: `glass` → `soft`. Baseline glass failed modeled
  panel text in **24/24** cases, minimum **2.39:1** against white behind the panel.
  Soft is the least opaque supported floating-panel enum passing this matrix;
  numeric `.96` panel opacity would be an unsupported API.
- Notification and OSD background opacity: `.92` → `.96` for elevated surfaces.
- Preserve approved bar padding **11**, outside spacing **10**, group spacing
  **12/14**, thickness **38**, capsule alpha **.92**, centered workspaces, and
  Adwaita Sans/ui_scale **1.20**, clock **1.08/600**, date **.94**. No spacing/type
  retuning after the user's earlier rejection of wider spacing/taller capsules.
- Dark/wallpaper/Matugen, semantic colors, control-center width **950**, functions,
  hooks, placement, keybinds, slanted carousel and original unframed Hyprlock are
  untouched by this change. No shell/plugin/island addition.

## Offline results and exact checks

`tests/check_palette_matrix.py` now has **12 fixtures × dark/light = 24 cases**:
cool, warm, green, muted, bright, dark, busy, pastel, neon, grayscale, muddy,
complementary. Busy uses a deterministic tighter wave/swirl. Synthetic fixtures
exercise palette extraction, not photographic/screenshot acceptance.

The matrix uses real Matugen output and native template rendering, checks role
parity between Matugen JSON and native output, and composites over black/white
wallpaper bounds. It models floating panel, Home card, sidebar, notification and
OSD settled surfaces, OSD progress/glyph states, and existing bar/workspace/terminal
checks. Text threshold **4.5:1**, essential glyph/progress **3:1**; decorative thin
outlines/shadows and third-party tray/artwork pixels are not essential-role tests.
Native contrast failures are collected per case and make the CLI exit nonzero.

| Model/check | Worst ratio |
|---|---:|
| Existing bar/workspace/terminal/semantic checks | 5.34 |
| Floating panel text | 5.52 |
| Home card text | 8.40 |
| Sidebar text | 8.04 |
| Notification text | 8.11 |
| OSD text, including Error | 5.61 |
| OSD essential glyph | 5.59 |
| OSD essential progress versus track | 5.83 |

Commands run from the selected worktree (passing test output suppressed):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/check_palette_matrix.py --no-desktop
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_palette_surfaces.py -q
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p check_palette_matrix.py -q
git diff --check -- config/noctalia/config.toml tests/check_palette_matrix.py docs/rice/QUIET_CURRENT_NATIVE_AUDIT.md
```

Results: **24 cases, 192 native template renders, zero contrast failures**;
**3 existing capsule tests + 2 new model tests**, no skips. Model tests cover blend
endpoints/reference contrast, a failing glass baseline, passing soft fallback and
an intentionally invisible essential glyph. Native validation ran the wrapper's
`config validate /home/admin/Projects/dotfiles/.worktrees/quiet-current/config/noctalia/config.toml`
with temporary HOME/XDG config/data/state/cache/runtime, display/session overrides
removed; exit 0, no WARN/ERROR. Negative controls used temporary TOML only.

All matrix subprocesses, including `stage_native`'s nested render calls, now share
the temporary HOME/XDG environment; display/DBus/Hyprland and Noctalia directory
overrides are removed. No template hooks/deployment run. Existing `stage_native`
uses `/usr/share/noctalia/assets/templates`; its catalog and all eight selected
template inputs were byte-identical to wrapper assets at inspection (including
the special `hyprland/hyprland.lua` input). No controller/pipeline code changed.

## Named gaps and handoff

- **Host/session evidence:** this agent's single sandbox `hyprctl configerrors`
  probe exited 2 (`Couldn't set socket timeout (2)`). Controller subsequently
  reported working authorized Desktop Commander host access with explicit env:
  `HYPRLAND_INSTANCE_SIGNATURE=efb50993780079460b0cbed1363e2166a2de1d9f_1793155626_697535192`,
  `XDG_RUNTIME_DIR=/run/user/1000`, `WAYLAND_DISPLAY=wayland-1`, Hyprland 0.56.2.
  Thus IPC is sandbox-limited, **not globally unavailable**. Controller owns
  configerrors/monitor/export/screenshot and 10-second CPU evidence; no duplicate
  probe/profile here. Reported host access is not this agent's independent result.
- **Renderer/visual acceptance:** sRGB channel blending is an offline model, not
  verified screenshot/GLES/Hyprland pixel math; blur, animation fades, all hover/
  disabled states, textured artwork, native input/focus, HiDPI/multimonitor and
  real 12-wallpaper screenshots remain pending. No FPS/resource/smoothness claim.
- **Binary provenance:** dirty compiled `5c1c69c8d69e` cannot be equated with clean
  source/assets `0d320287` or root `b98c8594`; no rebuild/parity proof performed.
- **Scope:** Phase 0 external repository/source-closure audits and other phases
  are not certified here; controller should combine concurrent owners' evidence.
  Live runtime overrides may change after this read-only inspection.

Inputs consulted: repository `AGENTS.md`, `README.md`, `docs/rice/{PLAN,STATE,VALIDATION,
2026-10-25-adaptive-unified,2026-10-25-adaptive-results,2026-10-25-bar-refinement}.md`,
`docs/plans/{task,2026-10-27-code-review-fixes}.md`; selected 2026-10-27 master prompt
and research design; native governance/wrapper and the targeted current sources
above. Current rollback is to undo only the three owned diffs in this worktree,
preserving other agents' work; no live rollback is required because nothing was
installed. Future live preview/reload requires its separately authorized flow.
