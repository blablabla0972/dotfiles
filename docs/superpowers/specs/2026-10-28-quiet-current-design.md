# Quiet Current / Tidal Glass — implementation specification

User selected this design in the supplied research package and authorized implementation on 2026-10-28. The original Master Implementation Prompt plus Additional Source Audit remain the detailed requirements; this file resolves their alternate illustrative names.

Global constraints: one transaction owner (`generate-theme.py`), wallpaper-derived semantic colors, native Noctalia, existing Lua compositor and slanted Quickshell carousel, dark default, existing launcher/input/lock behavior. Generated leaf files and live main remain untouched during development. Native preview and merge are separate approval gates.

Interfaces:
- Pure Python `config/rice/theme/derive_tokens.py`; strict RGB/mode/source hashes, WCAG luminance, sRGB compositing assumption pending screenshot calibration, deterministic schema1. No trusted image sampler means opaque surfaces, not a claim of wallpaper-region adaptation.
- Generated artifact `$XDG_STATE_HOME/desktop-wallpaper/adaptive-theme.json`: `schema_version`, `source_palette_sha256`, `wallpaper_sha256`, `mode`, semantic `colors`, `materials` with `opacity/style`, `motion` with `hover_ms/popup_ms/overlay_ms`, `quality` and contrast diagnostics. The transaction snapshots it and publishes last, restoring it on failure.
- Carousel commit CLI: `--apply-wallpaper --request-id ID --json IMAGE`. Exactly one JSON stdout record: `{schema_version,request_id,status,wallpaper,palette_revision,error_code}`. `applied` follows verification and final atomic publication; `rolled_back` requires successful managed-file/backend recovery; incomplete recovery is `failed`. Logs go to stderr. Wallpaper spelling in the record is absolute original input, including symlink spelling.
- Carousel ignores mismatched/duplicate replies, queues latest intent, treats timeout as unknown and preserves a running transaction when hiding its UI. Preview leaves live config/state unchanged; isolated generation may populate disposable XDG cache entries. Optional token consumption must fall back to native palette.
- User revision, 2026-10-28: remove card captions, persistent filenames and normal keyboard instructions; retain preview swatches and transient apply/error feedback. Cache both swatches and Matugen outputs by image contents, mode and generation inputs; a valid hit must avoid Matugen entirely.
- Normal text contrast >=4.5 plus .3 margin, essential controls >=3 plus .3; explicit unsatisfied result if opaque cannot pass. Native screenshot compositing remains a separate gate.

Rulings:
- No upstream source is transplanted. Reported mechanisms are conceptual references; this implementation is original against the supplied interfaces. No claim of complete audits of 54 projects.
- Keep adaptive tokens in XDG state to avoid generated repository churn. Install source `rice` alongside existing core components.
- No sampler/automatic effect service without trustworthy image decoding, supported reversible APIs and measured benefit. Full/Balanced/Reduced governor and native island/C++ changes remain conditional, not silently enabled.
- Provide `install.sh --no-state` so the explicit Noctalia preview selector cannot overwrite session/lock settings.

Acceptance: original 44 tests remain green; token, protocol, fault-injection and queue tests; native config validation; >=12 wallpaper offline matrix. Live QA needs a reachable compositor, A/B screenshots, actual contrast/performance, scales/input/lock/media/screen sharing and explicit preview approval. Do not certify these from offline output.
