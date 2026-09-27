# Task 159 brief — refused Insert Time on an unresolvable scope closes the keyboard ledger

# Context

The fork's rejected-insert path is the last open cluster in
`src/checks/rollcheck/proof.keyboard.txt`: an active time selection whose track scope
resolves to nothing is a refused command — no prompt, no mutation. The Swift production
path already carries the semantics (`AutomationSelectionCommands.resolvedSelectionScope`
at `src/swift/app/drawer/automation/AutomationSelectionCommands.swift:79-87` intersects
the scope with `usedTracks()` and returns nil when empty, so `transformSelection`
returns without touching the document), and the staging APIs are real production entry
points: `session.applyTimeSelection(AutomationTimeSelection(range:scope:))` and
`page.consumeSelectionCommand(command:)` are both exercised by the sibling check
`checkTimelineInsertBlankTimeTracks` (`src/checks/rollcheck/keyboard_timeline_insert.swift:54-79`).
No executing predicate stages the invalid scope, so the four rows sit GAP.

Selected **4 GAP rows (A077–A080)** in `src/checks/rollcheck/proof.keyboard.txt`
(pinned revision `a1244957`, `PianoRollTest::timelineInsertBlankTimeTracks`,
`src/checks/rollcheck/keyboard.cpp`):

| Target A-ids | Fork lines / clause |
|---|---|
| A077 | 624 — the fixture has a timeline-unused track (setup observation, no A-id on the predicate) |
| A078 | 631 — the invalid active scope is staged: primary/only-scoped track is the unused one, selection active with the exact range |
| A079 | 649 — the refused Insert Time opens no prompt |
| A080 | 651 — full invariance: SMF bytes, revision, undo index and count, cursor, and the staged selection all unchanged |

Setup-only rows: A077 (fixture guard). **Whole-ledger closure**: the remaining rows are
86 MATCHED + 15 RETIRED-REPRESENTATION; closing A077–A080 disposes every row, so the
ledger is deleted in the same commit. Its C++ source is already absent (deleted with
the pinned revision recorded in the ledger header); cite that pin in the deletion, and
re-verify no other ledger cites `proof.keyboard.txt` Swift sites.

# Exact write set

- `src/checks/rollcheck/keyboard_timeline_insert.swift` — one new `checkTimelineInsertRejectedScope(report:session:)` beside the existing functions.
- `src/checks/rollcheck/keyboard.swift` — one call line in `runKeyboardChecks`.
- `src/checks/rollcheck/proof.keyboard.txt` — deleted (whole-ledger closure).
- Conditional production repair, only if the journey exposes a real defect: `src/swift/app/drawer/automation/AutomationSelectionCommands.swift` or `src/swift/app/EditorCommandRouter.swift`.

# Prerequisites

None in-wave. Read sprint-3 §18 for shared constraints.

# Interface contract

Consume `DocumentSession`, `AutomationPage.attach/detach`, `EditKeyArbiter.decide`,
`page.consumeSelectionCommand(command: .insertTime)`, `session.applyTimeSelection`,
`session.editCursor`, `session.document.history` (`undoIndex`, `undoCount`,
`currentIdentity`), `document.state`/`revision`, and the page/ruler prompt state
(`promptOpen`/`insertTimePromptOpen` — the production flag `EditorCommandRouter`
reads at `src/swift/app/EditorCommandRouter.swift:37`) unchanged. The scenario seeds a
song, provisions a second track that stays empty (timeline-unused), stages the
selection with scope `.tracks([unusedTrack])` and the primary/active track set to it,
routes the command through the arbiter and the page, and observes the refusal. Expected
bytes/revision/index/count/cursor are literals captured before the command and compared
after — never the mutated result against itself.

# Implementation steps

1. Build the fixture: seed note on the used track, `addTrack(voice:)` for the unused
   track with no notes; assert the unused track exists (setup, no A-id).
2. Stage the invalid scope through the production selection APIs; assert the staged
   state (A078): scope resolves to the unused track only, selection active with the
   exact staged range.
3. Route `.insertTime` through `EditKeyArbiter.decide` and
   `consumeSelectionCommand`; assert no prompt state opens (A079).
4. Assert the full invariance list (A080) with independent before-literals.
5. Close A077 as setup, A078–A080 MATCHED with executed anchors, delete the ledger, and
   record the pinned-revision citation for the already-deleted C++ source.

# Acceptance predicate

A staged but unresolvable time-selection scope refuses Insert Time through the real
command path with zero document, history, cursor, selection and prompt effects — and
the keyboard ledger closes whole.

Named checks under §18 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
deno task proof list
```

`proof list` no longer reporting `src/checks/rollcheck/proof.keyboard.txt` is part of
the acceptance.

# Task-specific constraints

No new selection or scope API: staging must use the production entry points the mounted
surface itself uses. Do not disable the action as the refusal proof — the fork's clause
is a refused *execution*, and action-disable coverage already exists in
`tst_ShellWindowParameterKeys.qml`. Ledger deletion does not authorize any production
C++ removal. `session_io.swift`, `HostBehaviorChecks.swift` and `painting_raster.swift`
belong to sibling tasks; do not edit them.
