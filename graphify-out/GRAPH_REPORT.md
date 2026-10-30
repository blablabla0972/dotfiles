# Graph Report - dotfiles  (2026-10-30)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 486 nodes · 930 edges · 29 communities (8 shown, 21 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 23 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2142c27f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- json
- derive_tokens.py
- generate-theme.py
- AdaptiveTransactionTest
- ApplyStateTests
- ThemeSyncTest
- ThumbnailTests
- TestTier2BoundaryCorner
- InstallerSafetyTest
- TestTier1FeatureCoverage
- E2EEnvironment
- ApplyState.js
- install.sh
- TestTier3CrossFeature
- MatugenCacheTest
- PreviewCacheTest
- MatugenSafetyTest
- TestTier4RealWorld
- ToggleDesktopStateTests
- WrapperTests
- CapsuleContrastTest
- RiceInstallTest
- preview-quiet-current.sh
- SnapshotSafetyTest
- apply-wallpaper.sh
- generate-thumbs.sh
- wt-prep.sh

## God Nodes (most connected - your core abstractions)
1. `AdaptiveTransactionTest` - 23 edges
2. `ThemeSyncTest` - 22 edges
3. `apply()` - 18 edges
4. `ApplyStateTests` - 17 edges
5. `InstallerSafetyTest` - 17 edges
6. `wallpaper_changed()` - 17 edges
7. `tokens()` - 16 edges
8. `AdaptiveTokensTests` - 15 edges
9. `ThumbnailTests` - 15 edges
10. `command()` - 15 edges

## Surprising Connections (you probably didn't know these)
- `tokens()` --calls--> `derive_tokens()`  [EXTRACTED]
  tests/test_adaptive_tokens.py → config/rice/theme/derive_tokens.py
- `TestTier1FeatureCoverage` --inherits--> `E2EBaseTestCase`  [EXTRACTED]
  tests/test_e2e_tier1_feature_coverage.py → tests/test_e2e_common.py
- `TestTier2BoundaryCorner` --inherits--> `E2EBaseTestCase`  [EXTRACTED]
  tests/test_e2e_tier2_boundary_corner.py → tests/test_e2e_common.py
- `TestTier3CrossFeature` --inherits--> `E2EBaseTestCase`  [EXTRACTED]
  tests/test_e2e_tier3_cross_feature.py → tests/test_e2e_common.py
- `TestTier4RealWorld` --inherits--> `E2EBaseTestCase`  [EXTRACTED]
  tests/test_e2e_tier4_real_world.py → tests/test_e2e_common.py

## Import Cycles
- None detected.

## Communities (29 total, 21 thin omitted)

### Community 0 - "json"
Cohesion: 0.07
Nodes (18): compute_cache_key(), compute_image_sha256(), get_cache_dir(), get_matugen_identity(), main(), preview(), read_cached_swatches(), validate_swatches() (+10 more)

### Community 1 - "derive_tokens.py"
Cohesion: 0.08
Nodes (17): _check_envelope(), choose_surface_alpha(), composite_rgb(), _contrast_check(), contrast_ratio(), derive_tokens(), hex_to_srgb(), _normalize_palette() (+9 more)

### Community 2 - "generate-theme.py"
Cohesion: 0.13
Nodes (24): acquire_request_lock(), adaptive_path(), apply(), atomic_link(), atomic_write(), cached_matugen_outputs(), command(), inline_toml() (+16 more)

### Community 3 - "AdaptiveTransactionTest"
Cohesion: 0.11
Nodes (10): AdaptiveTransactionTest, event(), render(), write(), ipc(), fail_cleanup(), ipc(), ipc() (+2 more)

### Community 4 - "ApplyStateTests"
Cohesion: 0.13
Nodes (3): ApplyStateTests, PreviewHelperTests, QmlProcessTests

### Community 6 - "ThumbnailTests"
Cohesion: 0.21
Nodes (3): IsolatedHome, ThumbnailTests, ToggleDesktopTests

### Community 12 - "ApplyState.js"
Cohesion: 0.26
Nodes (6): adaptivePalette(), begin(), finish(), reduce(), resultFor(), validHash()

### Community 13 - "install.sh"
Cohesion: 0.35
Nodes (11): backup(), ensure_backup_dir(), err(), info(), is_valid_target(), link(), ok(), run() (+3 more)

## Knowledge Gaps
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AdaptiveTransactionTest` connect `AdaptiveTransactionTest` to `json`?**
  _High betweenness centrality (0.115) - this node is a cross-community bridge._
- **Should `json` be split into smaller, more focused modules?**
  _Cohesion score 0.06905671466353218 - nodes in this community are weakly interconnected._
- **Why does `ThemeSyncTest` connect `ThemeSyncTest` to `json`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Should `derive_tokens.py` be split into smaller, more focused modules?**
  _Cohesion score 0.08200290275761973 - nodes in this community are weakly interconnected._
- **Why does `TestTier2BoundaryCorner` connect `TestTier2BoundaryCorner` to `json`?**
  _High betweenness centrality (0.082) - this node is a cross-community bridge._
- **Should `generate-theme.py` be split into smaller, more focused modules?**
  _Cohesion score 0.13360323886639677 - nodes in this community are weakly interconnected._
- **Should `AdaptiveTransactionTest` be split into smaller, more focused modules?**
  _Cohesion score 0.11051693404634581 - nodes in this community are weakly interconnected._