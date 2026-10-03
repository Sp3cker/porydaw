# Task 123 brief — velocity gestures validate their frozen targets and finish once

# Context

Finish the existing velocity drawer's transaction and voice-resolution surface. The old model's rejection predicates are currently compared with SongDocument's unrelated clamp/last-write-wins API; that is not parity. Keep document batch semantics unchanged and put gesture validation in the existing frozen transaction. No later task consumes a new interface.

Verified planning selection: **31 open rows (27 GAP + 4 PARTIAL)** from sprint-3 §14.

- `src/checks/keyboard/proof.tst_velocitymodel.txt` — A001, A002, A003, A004, A005, A006, A008, A009, A010, A011, A012, A015, A016, A017, A018, A023, A024, A025, A030, A043, A055, A056, A067, A068, A069, A070, A071.
- `src/checks/drawerpresentation/proof.velocity.txt` — A041, A064, A088, A091.

Oracle: `fceecd88`; source pins respectively `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`, `f3069ef693542bdb63564b80a29773e2f5b2a360`. Read each selected expression with `deno task proof sites` / `show`.

# Exact write set

- `src/swift/app/drawer/velocity/VelocityTransactions.swift`
- `src/swift/app/drawer/velocity/VelocityInteraction.swift`
- `src/swift/app/drawer/velocity/VelocityContext.swift`
- `src/swift/app/drawer/velocity/VelocityScene.swift`
- `src/swift/app/drawer/velocity/VelocityPublication.swift`
- `src/swift/app/drawer/velocity/VelocityPage.swift`
- `src/checks/keyboard/tst_velocitygesture.swift`
- `src/checks/keyboard/tst_velocitymodel.swift`
- `src/checks/drawerpresentation/velocity.swift`
- `src/checks/drawerpresentation/velocity_context.swift`
- `src/checks/velocity/VelocityPaintDetentUnlockedChecks.swift`
- `src/checks/velocity/velocitydetentdragging.swift`
- `src/checks/editorqml/tst_EditorDrawerVelocityRaster.qml`
- `src/checks/editorqml/tst_EditorDrawerVelocityEditing.qml`
- The two selected proof files, owned only by the separate ledger writer.
- Conditional deletion only: `src/core/velocitymodel.cpp`, `src/core/velocitymodel.h`.

Closed list. Both ledgers can close after their entire inventories are resolved. The native pair is **not automatically freed**: retained `src/core/songdocument.cpp` includes velocitymodel.h. Apply §14's transitive retirement gate; keep the pair while any remaining open SongDocument/host obligation exercises it. No C++ include surgery is authorized here.

# Prerequisites

The split-600 wave and settled 108/112 velocity behavior. This task is independent of 118/119 and does not reuse their files, including their split drawer-parity suites.

# Interface contract

- Keep VelocityGestureState as the sole frozen target/preview owner and VelocityGesturePolicy as the computation owner. Make its existing initializer failable for invalid assigned IDs, out-of-domain 1...127 velocities and duplicate IDs; relative/ramp editing requires targets. Empty paint/band/pan setup remains legal until editing targets exist. Migrate every initializer caller listed above; do not change SongDocument.setVelocities clamping or batch ordering.
- Add `VelocityGestureState.updatePreview(_ updates: [NoteVelocity]) -> Bool`, mutating: validate the entire nonempty batch before writing, reject unknown/duplicate IDs and values outside 1...127, preserve the previous preview on failure, and keep untouched targets at their original values. Use it in the existing relative/ramp/paint producer, not only checks. Original values 40 and 120 must be queryable from a newly frozen editing gesture without painting transient ink before activation.
- A second press cannot replace a held editing transaction. Release consumes that transaction exactly once; inactive move/release and repeated cancel cannot produce a document edit. Prove bytes, revision, history index/count and preview at press, motion, cancel, stale release and fresh recovery. Retire only the deleted standalone model's Boolean/optional return shape where the actual owner proves the corresponding no-op; do not retire rejection, atomicity or retained-value behavior.
- Use VelocityContextPolicy.resolve with owned BankSlotView subvoice facts for invalid subgroup, nested subgroup, keyless split and the valid Programmable Wave child. Do not add a second raw ToneData resolver. Preserve per-key map identity and repeat the playhead-context observation for direct sound, square, wave and noise.
- Drawer A041 samples bar ink beyond the authoritative timeline length, not beyond cameraScrollX. A064 samples literal black at the fork's outsider probe, with independent position/color and the original tolerance. A091 proves all transient geometry is empty after release/cancel and the corresponding pixels return; a handful of cleared pixels alone is insufficient.

# Implementation steps

1. Replace the wrong document-batch surrogates in the registered velocity gesture cases with the real frozen-gesture contract; delete incidental surrogate assertions rather than rewording them into proof.
2. Integrate validated construction/update and exactly-once completion in the existing drawer transaction; preserve paint/ramp activation and early/late detent unlock.
3. Extend existing context and mounted velocity journeys for the selected subvoice, timeline-end, outline and transient predicates.
4. Supply settled executed anchors to the separate ledger writer; close/delete the two ledgers and conditionally retire the native pair only under the stated gate.

# Acceptance predicate

The musical-semantics lane executes the model/gesture checks; projectsession executes the drawer context checks; actual drawer pointer input proves staging and cancellation. All selected clauses execute without a new gesture or a second state owner.

The implementer runs these covering lanes under §14's lock policy; the controller runs the settled-group gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-musicalsemantics --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No core document/history, automation, shared shell runner or checked-in fixture writes. Keep every code file at most 600 lines; the transaction fits its existing concept file. Swift symbol-reference discovery must be refreshed before the initializer change: planning's sourcekit query failed to load the standard library and was not used as evidence of complete references.
