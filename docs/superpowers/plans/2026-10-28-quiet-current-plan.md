# Quiet Current — execution plan

Spec: `../specs/2026-10-28-quiet-current-design.md`.
Base: `6b832a8c0e85377b1617b2d474dd6db82df3a851`; branch `feat/quiet-current`, worktree `.worktrees/quiet-current`.

1. P0: preserve user changes/worktrees, record versions/symlinks/fork evidence, run baseline, resolve source/API ownership. Done when evidence and named live gaps are recorded.
2. P1: implement pure semantic token library and tests before integration; test both modes, invalid input, unknown sampling, contrast, endpoints and deterministic serialization.
3. P2: integrate derived artifact into snapshot/rollback and all writer paths; final commit acknowledgment, stable revision capture, failure injection and state-preserving installer option.
4. P3: implement real acknowledged apply, latest-intent queue, readable pending/error and optional read-only preview; preserve input/geometry; test rapid events and failure/timeout/reply ordering.
5. P4: supported native config polish and explicit source/API evidence; >=12-case offline palette matrix and native validation, without modifying native state or C++ fork.
6. P5: evaluate governor prerequisites; if live benchmarks unavailable, record conditional deferral and ship no persistent sampler/service.
7. P6: full offline regression/static validation, fresh independent branch review and fixes; prepare exact preview/rollback commands. Live QA remains pending until session access and approval.
8. P7: optional native island/fork only under its separate authorization and complete source/maintenance review.

Shared interfaces: P1 schema consumed by P2 and P3; P2 stdout outcome consumed by P3. Resolve against Spec; never derive success from animation timing.

Execution ledger: `../../rice/QUIET_CURRENT_STATE.md`. Each completion records commands/counts and remaining gates. User changes at main and fork root are outside this branch. No push or merge during development.
