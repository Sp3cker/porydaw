# Task 112 brief — velocity selection and roll cancellation preserve document state

# Context

Finish the velocity drawer/roll handoff: literal press preview, continuous axis, temporary band selection, cancellation publications, stationary playback values and octave edits. Consume 108's settled detent transaction; do not change its value mapping to satisfy a different gesture.

Verified planning selection: **35 open rows (2 GAP + 33 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/velocity/proof.tst_velocityediting.txt` — A018, A075, A121, A122, A123.
- `src/checks/velocity/proof.velocityclicks.txt` — A002, A003, A043, A048.
- `src/checks/velocity/proof.velocityroll.txt` — A001, A002, A003, A010, A011, A040, A047, A048, A052, A053, A054, A082, A083, A102, A103, A107, A108, A109.
- `src/checks/velocity/proof.velocityselection.txt` — A010, A011, A037, A038, A040, A041, A054, A055.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `f3069ef693542bdb63564b80a29773e2f5b2a360`, `f842f7e128adea2958d0967e2afbd834893f21b4`, `7607c6d7bd5f86c4f29244eb17aa2f5b54dc145e`, `c9e901546626af1df12471504999c581e5eb4519`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift`
- `src/swift/app/drawer/velocity/VelocityInteraction.swift`
- `src/swift/app/drawer/velocity/VelocityTransactions.swift`
- `src/swift/app/drawer/velocity/VelocityPublication.swift`
- `src/swift/app/roll/PianoGrid.swift`
- `src/swift/app/roll/PianoGrid+Gestures.swift`
- `src/swift/app/roll/NoteCommands.swift`
- `src/checks/velocity/tst_velocityediting.swift`
- `src/checks/velocity/VelocityRollCoreChecks.swift`
- `src/checks/velocity/VelocityClickSelectionChecks.swift`
- `src/checks/velocity/VelocityClickCancellationChecks.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/velocity/proof.tst_velocityediting.txt`
- `src/checks/velocity/proof.velocityclicks.txt`
- `src/checks/velocity/proof.velocityroll.txt`
- `src/checks/velocity/proof.velocityselection.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 and Group A's checkpoint precede this task. Rebase velocity production over 101/108, tst_velocityediting over 101, PianoGrid/NoteCommands over 102/105/109, and shell-grid input over 105/109. The source inspection must preserve 108's committed raw-value/ramp predicates.

# Interface contract

- Keep `VelocityInteraction` preview/selection ownership, `VelocityTransactions`' release/cancel boundary and roll `PianoGrid`/`NoteCommands` commit ownership. Cancellation publishes zero document and edited/dirty changes and leaves all three exact document and timeline velocities unchanged. Assert each selected row at its own cancel boundary, not after a later reset.
- In velocityediting A018 observe the continuous axis in its own paint journey; A075 observes canRedo immediately after Undo; A121–A123 observe all three exact playback velocities after stationary press/release. For clicks A043/A048 compare preview and committed value to the independently calculated pressed literal, not the preview to itself.
- Roll A010/A011 places the press strictly inside the painted note's actual rectangle. A040 observes selection during the held press; A047/A048 and A082/A083 count zero session publications for their respective cancellation journeys. A052–A054 and A107–A109 each observe the three exact timeline velocities after cancellation and octave edit. A102/A103 observe exactly one document and edited publication for octave change.
- Selection A010 observes the correct axis after a real primary-track switch and A011 exactly five graduations. A040/A041 observe the exact expanded and contracted intermediate selection-band bounds before release, plus resulting note selection; final membership alone is not enough. Do not infer the band from the same producer geometry used to construct it.
- clicks A002/A003, roll A001/A002/A003 and selection A037/A038/A054/A055 are native fixture coordinate/identity prerequisites. Retire their representation while preserving real blank-space no-hit, note targeting and band traversal. The five pre-existing NATIVE-SETUP rows in velocityediting must also be classified explicitly against their original source before ledger deletion; they are not five additional GAP/PARTIAL rows or permission for setup tests.
- Deliver Escape and octave keys in `tst_ShellGridInput.qml`, whose mounted ShellWindow owns them. Do not move those clauses into the editor-only drawer lane or call an octave command directly as the sole key-delivery witness.

# Implementation steps

1. Extend the existing VelocityRollCoreChecks, VelocityClickSelectionChecks/VelocityClickCancellationChecks and tst_velocityediting journeys at their actual held/cancel/undo/stationary/octave boundaries. Use literal expected values and independently counted session publications.
2. Exercise mounted blank-space input, band expansion/contraction, roll velocity cancellation and octave keys in tst_ShellGridInput. Keep the actual window dispatcher present throughout the key scenarios.
3. Repair only demonstrated selection/preview/cancel/commit divergence in the declared velocity/roll owners; preserve 108's raw detent law and 102's remapping.
4. Map the 35 selected rows, classify the pre-existing five NATIVE-SETUP obligations without padding the row budget, and delete each of the four ledgers once its entire inventory is closed.

# Acceptance predicate

The existing VelocityPage registry executes the selected velocity checks in swiftcore-projectsession; shell-grid-input proves the real roll/chrome keys and mounted band/cancel behavior. All 35 selected rows close and the five legacy setup classifications are resolved before deleting the four ledgers.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No EditorSurface.qml, ShellWindow, EditKeyArbiter, task-108 check source or drawerpresentation/velocity row writes. A grid configured with dpr=2 in Swift is not proof of a DPR2-rendered QML lane.
