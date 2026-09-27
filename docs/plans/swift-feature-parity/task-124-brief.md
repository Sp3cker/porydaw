# Task 124 brief — lane clipboard scope uses ordered endpoints and half-open hit coverage

# Context

Complete the existing automation range/clipboard selection surface, not a new stacked-lane interface. The row catalog already owns lane identity and coverage, but endpoint resolution and physical display-space selection hit testing have no shared production implementation. Task 125 consumes the same typed lane identities when tracks remap.

Verified planning selection: **20 open rows (20 GAP + 0 PARTIAL)** from sprint-3 §14.

- `src/checks/clipboard/proof.clipmime_test.txt` — A017.
- `src/checks/clipboard/proof.laneselection_test.txt` — A010, A011, A053, A054, A055, A056, A057, A058, A059, A061, A062, A063, A064, A065, A066, A067, A068, A069, A070.

Oracle: `fceecd88`; source pins respectively `02752345fa3a1dbaf11ee6f1cd3ad5da475f0e06`, `17942fef3dff1fce4d45c7b1aac7428f3027f395`.

# Exact write set

- `src/swift/app/drawer/automation/AutomationLaneProjection.swift`
- `src/swift/app/drawer/automation/AutomationGestureEditing.swift`
- `src/swift/app/drawer/automation/AutomationSelectionCommands.swift`
- `src/checks/editcheck/SelectionChecks.swift`
- `src/checks/editcheck/SelectionTrackChecks.swift`
- `src/checks/editcheck/ClipboardCodecChecks.swift`
- `src/checks/editorqml/tst_EditorDrawerAutomationTransactions.qml`
- `src/checks/editorqml/tst_EditorDrawerAutomationLaneMenu.qml`
- `src/checks/editorqml/tst_ShellClipboardRoundTrip.qml`
- The two selected proof files, owned only by the separate ledger writer.

Closed list. Both ledgers are conditional full closures. Their original C++ checks are already absent. No native production deletion is yet authorized: songdocument_range.cpp additionally needs task 125 and the remaining transitive SongDocument obligations; songdocument_timeeditor_insert.cpp additionally needs the unselected roll keyboard A077–A080; smf.cpp/h additionally serve onboarding import, visual dialogs and other open ledgers. Record these blockers instead of deleting a shared unit on two passing ledgers.

# Prerequisites

The settled split layout and existing range clipboard commands. No task-118/119 interface is required, and none of their files is writable here. Task 125 waits for this typed scope contract and 118's accepted state producer.

# Interface contract

- Add `AutomationRowStack.laneSet(from: AutomationParameter, through: AutomationParameter) -> (tempo: Bool, lanes: [AutomationParameter])`. Resolve inclusive endpoints in the existing row order independently of activeTickRange. Tempo-only yields true/empty; CC7-only yields false/[CC7]; Tempo through CC10 in the fork's Tempo/CC7/CC10 stack yields true/[CC7,CC10]; reversed endpoints yield the same ordered payload; either missing endpoint yields false/empty. Do not substitute a Set where output order is specified.
- Add `AutomationRowStack.hitTest(parameter: AutomationParameter, x: Double, projection: AutomationProjection, selection: AutomationTimeSelection) -> Bool`. Use the projection's actual DPR and camera to test the displayed half-open interval, not a snapped tick. For [48,96), CC7 hits at start and midpoint, misses one logical pixel before start and at end; CC10 and Tempo miss when outside scope. Reversed/inactive selection misses. Execute all four original zoom/scroll/DPR table rows.
- Route the existing band's lane payload and selection-preservation hit decision through these methods in AutomationGestureEditing/AutomationSelectionCommands. A normal one-lane gesture uses equal endpoints; multi-endpoint model inputs prove the existing fork contract without adding a cross-tab drag or stacked-lane widget. Keep current event-count coverage and selected-node move behavior.
- Deliver actual right-band and copy/paste menu input to the mounted drawer. Pressing just outside/at the exclusive endpoint must not accidentally preserve the selected band through snap rounding. Copy payload and paste result must name the intended lane only, with exact bytes/history through Undo; cancellation leaves original bytes and no staged write.
- clipmime A017's native decodeFailed output parameter is a representation, not a reason to invent a Swift flag. Retire that form only with the actual malformed-custom-MIME paste refusal, unchanged native clipboard/selection/cursor/document/history, and successful subsequent valid paste. A decoder-only nil result is not the mounted refusal witness.

# Implementation steps

1. Add endpoint resolution and display-space hit coverage to the existing row-stack owner, with the exact fork tables in registered selection checks.
2. Replace the current snapped-tick hit decision and one-off payload assembly at the existing production consumers; preserve current gesture vocabulary.
3. Extend the split drawer and native clipboard journeys for real boundary input, cancellation and recovery; use independently derived coordinates.
4. Have the separate ledger writer map the selected clauses and delete both ledgers only when their complete inventories are closed.

# Acceptance predicate

The registered session/time lanes prove exact scope and malformed decoding; mounted drawer/native clipboard lanes exercise the consuming gestures. The DPR2 run observes DPR 2 and real image dimensions before claiming a DPR2 hit boundary.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --filter swiftcore-timeedits --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
QT_SCALE_FACTOR=2 /usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --filter editorqml-drawer --verbose --qt EditorDrawerLane::test_productionAutomationDomainRowsThroughInput
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-clipboard-round-trip --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No AutomationPage, content/overlay publication, AutomationPlot, ShellDrawerParity, runner, registration, core time-edit or checked-in fixture writes. Keep every code file at most 600 lines; the new row-stack methods belong in the existing projection concept, not a parallel selection model.
