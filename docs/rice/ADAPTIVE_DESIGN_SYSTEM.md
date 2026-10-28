# Quiet Current / Tidal Glass — adaptive tokens v1

Phase 1 provides a pure standard-library module at
`config/rice/theme/derive_tokens.py`. It returns a dictionary; it performs no
file I/O, image decoding, process execution, live configuration changes, or
palette generation. Dark remains the pipeline default; both modes are supported.

## Integration boundary

The controller chose **`${XDG_STATE_HOME:-$HOME/.local/state}/desktop-wallpaper/adaptive-theme.json`**
as the artifact path. The existing theme pipeline owns its atomic publication,
allowlist, snapshots, revision validation, and rollback. This module never writes
the artifact. Pipeline integration and consumers belong to later phases.

Supply SHA-256 digests of the validated palette bytes and wallpaper bytes. Both
must contain exactly 64 hexadecimal characters and are emitted in lowercase.
The pure API validates their format; the caller verifies their provenance and
that samples belong to the same wallpaper revision and mode. A valid hash alone
does not imply that the wallpaper was sampled.

## Public API

```python
hex_to_srgb(color) -> tuple[float, float, float]
relative_luminance(color) -> float
contrast_ratio(foreground, background) -> float
composite_rgb(foreground, background, alpha) -> str
choose_surface_alpha(text, surface, wallpaper_samples,
                     candidates=(0.72, 0.82, 0.90, 0.96, 1.0), min_ratio=4.5) -> float
derive_tokens(matugen_palette, wallpaper_sha, palette_sha, mode, samples=None) -> dict
```

Colors strictly match `#RRGGBB` (either case on input, uppercase on output).
Alpha values must be finite numbers in `[0, 1]`; booleans are rejected.
Candidates must be nonempty and are considered in ascending numeric order.
`min_ratio` must be finite and in `[1, 21]`. Samples accept a list or tuple of
strict colors, `None`, or an empty sequence. Invalid input raises `ValueError`.

## Palette normalization and semantic mapping

Accept `{"dark": {...}, "light": {...}}` with either custom Noctalia `m*` roles
or native Noctalia snake_case roles in the selected branch. A flat palette must
declare `"mode": "dark"` or `"mode": "light"`. The requested mode must be present
and agree with any mode metadata. Mixed role schemes or simultaneous flat and
mode-wrapped roles are ambiguous and rejected. Missing required roles and
invalid consumed colors are rejected. Only the selected mode is consumed;
unrelated extensions such as terminal colors are ignored. Input palettes need
no version field; any supplied `schema_version` must be integer `1`.

The existing `config/noctalia/palettes/matugen.json` and its source template
`config/matugen/templates/noctalia-palette.json` confirm the custom roles. In that
template, `mSurfaceVariant` comes from Matugen `surface_container_low`, `mHover`
from `surface_container_high`, and `mOutline` from `outline_variant`. The native
names below are Noctalia role names, not a raw Matugen export adapter.

| Output color | Custom role | Native role |
| --- | --- | --- |
| background | mSurface | surface |
| surface_low | mSurfaceVariant | surface_variant |
| surface | mSurfaceVariant | surface_variant |
| surface_high | mHover | hover |
| text_primary | mOnSurface | on_surface |
| text_secondary | mOnSurfaceVariant | on_surface_variant |
| accent | mPrimary | primary |
| on_accent | mOnPrimary | on_primary |
| outline | mOutline | outline |
| focus_ring | mPrimary | primary |
| danger | mError | error |

`mHover`/`hover` is optional; surface_high falls back to surface_low. The eight
other input roles are required. Surface and surface_low intentionally share the
existing low-container color; Phase 1 does not invent intermediate colors or
repair a failing palette. Outline is decorative and carries no essential focus
or text guarantee. Use focus_ring for essential focus indication.

## Contrast and material policy

WCAG luminance linearizes each encoded sRGB channel: `c / 12.92` when
`c <= 0.04045`, otherwise `((c + 0.055) / 1.055) ** 2.4`, then weights RGB by
`0.2126`, `0.7152`, `0.0722`. Contrast is `(Lmax + 0.05) / (Lmin + 0.05)`.

The **unverified renderer assumption** is encoded sRGB channel blending,
`surface * alpha + wallpaper * (1 - alpha)`, quantized to the nearest byte with
half-up rounding. Thus half white over black is `#808080`. No screenshot or
actual Qt/Hyprland pixel comparison has been performed. The 0.3 contrast margin
does not prove this assumption; screenshot validation is required before a
consumer claims renderer-verified contrast.

Each material selects the smallest default candidate meeting **all** applicable
ratios over **every** supplied sample: normal text_primary/text_secondary >=4.8
(4.5 + 0.3), essential accent/focus_ring/danger icons >=3.3 (3 + 0.3). Neutral
icons may use text_secondary. On_accent is checked against an opaque accent at
>=4.8. Danger here is an icon role; danger-colored normal text needs its own
4.8 check. Foregrounds are assumed opaque. Bar uses surface_low, panel uses
surface, and notification uses surface_high. Style is `balanced` below opacity
1 and `solid` at opacity 1.

`choose_surface_alpha` applies the same 0.3 margin to its requested ratio and
checks the worst sample. Returning 1.0 is a fallback, not a success signal.
`derive_tokens` reports the ratios and pass/fail state at the actual selected
opacity. If no candidate passes, the material becomes solid. A failed on_accent
pair makes all materials solid. Failures that remain opaque are explicitly
listed; consumers must inspect `contrast.satisfied` and must not declare an
unsatisfied palette accessible merely because it is solid.

Without samples, every material uses opacity **1.0 / solid** and contrast basis
`opaque`. This is also the API's manual opaque path: pass `samples=None` or `[]`.
Opaque colors still undergo checks and may fail. Samples are optional,
caller-validated regional colors covering the locations where surfaces render;
all provided samples are checked for each material. No average, image metadata,
hash, or palette color is substituted for wallpaper sampling. Callers must
bound sampling work and supply adequate regional coverage; a passing sample set
does not prove contrast for unsampled pixels or arbitrary image content.

## Output and deterministic serialization

Schema version `1` contains `source_palette_sha256`, `wallpaper_sha256`, `mode`,
the eleven `colors` above, `materials` (`bar`, `panel`, `notification` with
`opacity`/`style`), `motion`, and `quality`. Motion is fixed at hover 120 ms,
popup 190 ms, overlay 240 ms. Quality is always `balanced`.

The additional `contrast` diagnostics contain `basis` (`samples`/`opaque`),
`sample_count`, `safety_margin`, `renderer_model="srgb_channel_blend"`,
`renderer_verified=false`, aggregate `satisfied`, sorted `unsatisfied_roles`,
and `checks`. Check names are `on_accent` or `<material>.<color_role>`; each
records the unrounded worst-case `ratio`, margin-inclusive `minimum`, and
`satisfied`. Diagnostics describe the mathematical model, not measured pixels.

No timestamps, random values, environment lookup, or input mutation occur.
Dictionary construction order is stable even when palette keys or samples are
reordered. For canonical artifact bytes, the pipeline can serialize with
`json.dumps(result, sort_keys=True, separators=(",", ":"), allow_nan=False)`.

## Verification and handoff

```sh
PYTHONDONTWRITEBYTECODE=1 python -B -m unittest discover -s tests -p test_adaptive_tokens.py -q
```

The 25 offline tests cover 21:1 and 1:1 contrast, the sRGB transfer breakpoint,
channel weights, alpha endpoints and rounding, strict validation, both modes
and adapters, 12 diverse synthetic sample sets in each mode, worst-sample
selection, safety margins, fail-closed diagnostics, purity, and stable JSON.
The test-first run failed because the module was absent; the implemented module
passes the targeted suite. Live screenshot validation and pipeline publication
remain outside Phase 1. Reverting these three source/test/document files removes
Phase 1; there is no generated artifact or live state to restore.
