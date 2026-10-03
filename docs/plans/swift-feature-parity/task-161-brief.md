# Task 161 brief — document mutation, undo and redo transitions around a live velocity gesture

# Context

The deleted host-integration suite's mutation cluster is unclaimed by any executing
predicate: while a velocity gesture holds its preview, a document mutation advances the
revision and appends one undo entry; undo rewinds the cursor; redo advances it. The
Swift owners are `DocumentSession`/`SongHistory` (`undoIndex`, `undoCount` —
"Mirrors QUndoStack::count()", `undoDocument()`, `redoDocument()` at
`src/swift/core/SongHistory.swift:231-236,374-391`) and the velocity page gesture APIs
already driven by `HostBehaviorChecks.swift::hostVelocityGestureContracts/
hostVelocityExactGestures`. The check host is the executing
`swiftcore-projectsession` lane (`SessionChecks.swift` invokes `runHostBehaviorChecks`),
so no registration changes.

Selected **7 GAP rows (A127–A133)** in `src/checks/host/proof.tst_hostintegration.txt`
(pinned revision `c17d966f`, `documentMutationUndoRedoAndReloadPreemptPreview`,
`src/checks/host/tst_hostintegration.cpp`):

| Target A-ids | Fork lines / clause |
|---|---|
| A127, A128, A129 | 564,565,566 — a velocity mutation advances revision by one, undo index by one and undo count by one |
| A130, A131 | 572,573 — undo advances revision by one and moves the undo index back by one |
| A132, A133 | 580,581 — redo advances revision by one and moves the undo index forward by one |

Setup-only rows: none selected (the gesture-begin/preview and trailing
preview-cleared clauses are already MATCHED/RETIRED — A134–A138 disposed). The reload
branch of the fork scenario stays unselected; its obligations live with the
lifecycle-termination PARTIALs.

# Exact write set

- `src/checks/host/HostBehaviorChecks.swift` — one new `hostDocumentMutationUndoRedo(_ report:...)` function invoked from `runHostBehaviorChecks`.
- `src/checks/host/proof.tst_hostintegration.txt` — A127–A133 only.

# Prerequisites

None. Read sprint-3 §18 for shared constraints.

# Interface contract

Reuse `hostTwoNoteSession` staging and the gesture begin/update/commit APIs the
neighboring functions already exercise. The journey: begin a real velocity gesture on a
seeded note, capture baseline revision/undoIndex/undoCount/currentIdentity, then for
each fork branch observe through the production APIs —
`document.setVelocities(_:expectedRevision:)` for the mutation,
`history.undoDocument()`/`history.redoDocument()` for undo/redo — asserting the exact
delta literals (revision +1; index ±1; count +1 on mutation only). Expected values are
independent literals derived from the captured baseline; identity continuity may
compare only against the pre-transaction capture. All three branches run in one
function on freshly staged state per branch, restoring the fixture between branches.

# Implementation steps

1. Stage the two-note session and gesture state as `hostVelocityExactGestures` does.
2. Mutation branch: capture baseline, mutate through the production API, assert the
   three +1 deltas (A127–A129).
3. Undo branch: mutate, capture, `undoDocument()`, assert revision +1 and index −1
   (A130–A131).
4. Redo branch: mutate, undo, capture, `redoDocument()`, assert revision +1 and
   index +1 (A132–A133).
5. Close A127–A133 MATCHED with executed message anchors in the same commit.

# Acceptance predicate

The document-history contract the host relied on — mutations append exactly one undo
entry and advance the revision; undo/redo move the cursor one step with a revision bump
each — is proven through the real session APIs with per-clause executed evidence.

Named checks under §18 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No host window, no native observation and no QML surface is claimed — these are
service-level document semantics. Do not relabel A114–A120 lifecycle PARTIALs, and do
not touch A162/A174–A185. `HostBehaviorChecks.swift` is around the 600-line review
signal: the new function is the same host-observation concept; no split, no new file,
no `SessionChecks.swift` edit.
