# MIDI backups

## Tasks
1. Module extraction (SDD-track): move the single storage implementation to the Foundation-only `PorydawBackups` Swift package, compile that same source in the app, and migrate callers.
2. Standalone regressions (SDD-track): move filesystem/retention checks to Swift Testing; leave document/save integration in the existing project-session lane.

These tasks run in parallel with disjoint write sets and the interface in [spec.md](spec.md). The controller owns task registration, documentation, verification, and incremental-build measurements. This revises the uncommitted feature; no commit or merge is authorized.

## Global Constraints
- Work only in this worktree. Preserve unrelated behavior and original-check provenance. No new C++. `PorydawBackups` depends only on Foundation; no Porydaw/Qt dependencies, wrappers, re-exports, or duplicate implementation. QML only launches the OS URL request.
- Follow [spec.md](spec.md). No undo replay, restore UI, new preferences, crash-marker system, or cleanup on exit.
- SHARED_TREE: implementers skip builds, tests, lint and formatters; perform read-only local structural inspection and report unavailable LSP honestly. Controller runs named gates on the settled union, formats once, and supplies behavioral evidence before review. Reuse named commands; report stale commands rather than narrowing coverage.
- Do not change existing proof-covered predicates or ledgers. If unavoidable, report exact affected ledgers; controller delegates proof-only reconciliation after sources freeze.
- Errors must be observable. A failed pre-save backup prevents the MIDI overwrite. Do not hide failures or silently disable backup protection.
- Existing save conflict, bank ordering, dirty/history and revision semantics remain intact. No save on timer; snapshots never mark a document clean.
