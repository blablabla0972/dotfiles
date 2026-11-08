# Parallel audit — 2026-11-08

Requested Luna was unavailable in this session; eight actual GPT-6.1 Sol agents
used max reasoning, with six concurrent slots and two subsequent launches.
Baseline: `1ac4ba3`; candidate: `.worktrees/multi-audit-20261108`.

| Agent | Independent audit scope |
| --- | --- |
| Einstein | Installer backups and failure handling |
| Hubble | Worktree preparation and source preservation |
| Cicero | Preview state transitions and stale completions |
| Plato | Carousel selection, aliases, pointer and keyboard handling |
| Epicurus | Preview rendering/cache identity |
| Bohr | Theme event ordering and suppression markers |
| Bernoulli | Native template staging and snapshot/storage paths |
| Faraday | Runtime configuration/startup; no new runtime defect confirmed |

## Verified changes

- Installer rejects a directory containing its checkout before backup; physical
  source paths survive invocation through a destination alias. Failed linking
  restores the prior destination while keeping the original exit code; recovery
  cannot overwrite a concurrently appearing unknown destination.
- Worktree preparation preflights both inputs before mutation, including every
  component/symlink hop that removal could invalidate. Relative symlinks are
  rebased to original referents, including dangling GPU links; valid chains remain
  supported. The helper uses the repository's existing Python runtime requirement.
- Failed previews can retry the same image/mode with a new request ID, while
  stale completions are still rejected and successful/pending selections do not churn.
- Carousel initial selection handles linked libraries and external image aliases;
  blank taps close it without closing card clicks or drags. Timeout/geometry remain.
- Preview hashing and Matugen rendering use the same private snapshot, preventing
  A→B→A source replacement from poisoning A's cache; protocol paths remain original.
- Matching event markers suppress work only while a transaction owns the lock.
  Queued mode events reconcile a genuinely differing native wallpaper and link,
  while native wallpaper ownership prevents duplicate manual backend writes.
- Native staging gives each render a distinct scratch filename even when the
  schema-accepted builtin template ID list contains duplicates.

## Evidence and limits

Reproductions ran in temporary files or mocked/offscreen processes, with observed
red/green regressions. Integrated checks: 206 unittests passed without skips,
24 native palette cases passed, shell syntax and diff checks passed. Independent
reviews caught and corrected recovery-clobber, backend-ownership and intermediate
symlink-hop issues before integration. Normal mode-only tests still assert no
wallpaper/backend changes; mismatched-selection cases are separate regressions.

Qt pointer/key coverage uses offscreen execution, not live visual acceptance.
No forced lock, suspend or service restart was used. Existing MIME/Micro edits,
generated files and preview styling are preserved; only reviewed helper/QML
changes are applied to the existing active Quickshell preview.
