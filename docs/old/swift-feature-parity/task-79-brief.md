# Task 79 brief — automation selected edits reach playback, atomically and reversibly

# Context

Own the mounted Automation drawer's selected-drag/Delete/undo/redo journey, plus
its single-node commit. The gap is the complete consumer-visible transaction,
not another automation model or a ledger cleanup. Existing checks observe
stored values but omit the actual playback projection, horizontal range
translation, raw Tempo preservation and some preview/publication boundaries.

1. **Verified census: 24 PARTIAL behavior rows.** `deno task proof sites
   automation/proof.automationselection.txt --status PARTIAL` gives this exact
   selected set: A015, A020, A039, A041, A052, A053, A054, A055, A061, A067,
   A075, A081, A088, A089, A095, A099, A116, A117 (**18**). The same command for
   `automation/proof.tst_automationediting.txt` gives A018, A019, A024, A025,
   A030, A031 (**6**). No GAP or representation row is selected. Remaining
   automation routing, raster, hover, voice and selection rows stay unchanged.
2. **Fork laws**, read at `fceecd88`:
   - `src/checks/automation/automationselection.cpp:230-249`: a horizontal
     Tempo drag keeps the document frozen while held, then moves the exact
     499999-us event to tick 144 and publishes it into playback.
   - `:274-358`: selected Tempo + Pan + LFO drag from 96 to 144 keeps Pan's
     two same-tick values `[10, 20]` in order and LFO `[96]`, preserves Volume,
     emits one edit, translates the selected interval to `[144, 192)`, and
     restores/reapplies the actual timeline on undo/redo.
   - `:361-435`: Delete from the displayed Tempo tab removes all covered
     lanes, not just the displayed lane; playback no longer contains their
     events. Undo restores raw Tempo; redo deletes again; an empty range
     creates no transaction.
   - `:475-495`: a document-rebuild cancellation keeps the original selection
     and playback events; the later release cannot commit a stale draft.
   - `src/checks/automation/tst_automationediting.cpp:42-94`: a real CC drag
     commits value 84 at tick 48, leaves the independent value 100 at tick 96,
     then playback reads 40/100 after undo and 84/100 after redo. A prompt
     acceptance is not equivalent to this pointer gesture.
3. **Current Swift/QML**, verified after the split:
   - Production `AutomationPage.qml:32-45` owns the mounted page and reads the
     document's page presenter. `DocumentWorkspace.swift:122-124,226-228`
     creates and attaches that same page. Paths here are under
     `src/ui/songview/quick/drawer/` and `src/swift/app/`, respectively.
   - `src/swift/app/drawer/automation/AutomationInteraction.swift:222-285`
     `releasePlot` applies `AutomationNodeResolver.moves`, then shifts the
     selection only for a committed nonzero selected time drag.
     `AutomationEdits.swift:181-225,236-270` owns atomic move/delete plans and
     source-order preservation; `AutomationSelectionCommands.swift:34-62`
     owns selected Delete and never falls through to notes.
   - `src/checks/automation/automationselection.swift:9-41` currently drives
     a vertical Pan/Volume/Tempo value drag. It is not the fork's horizontal
     Pan/LFO/Tempo collision fixture. `:183-218` checks a Tempo drag against
     stored values, not playback. Keep these useful existing scenarios.
   - `src/checks/automation/tst_automationediting.swift:8-43` currently
     exercises a value prompt and history. Add a genuine CC pointer-drag
     scenario rather than mapping that prompt to the fork drag.
   - `AutomationPageChecks.swift:119-168` builds a real document/session/page;
     `:182-201` reads document lanes and rounded BPM. Playback is separately
     available as `PlaybackTimeline.events/tempoMap`
     (`src/swift/core/PlaybackTimeline.swift:17-24,53-59,143-146`).
   - `src/checks/editorqml/tst_ShellGridInput.qml:48-75` opens Route 101 in
     production ShellWindow and resolves its mounted editor. Reuse that
     fixture for the real pointer/key smoke, not a new harness.

# Exact write set

- `src/swift/app/drawer/automation/AutomationInteraction.swift`
- `src/swift/app/drawer/automation/AutomationEdits.swift`
- `src/swift/app/drawer/automation/AutomationSelectionCommands.swift`
- `src/checks/automation/AutomationPageChecks.swift`
- `src/checks/automation/automationselection.swift`
- `src/checks/automation/tst_automationediting.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/automation/proof.automationselection.txt` — only the 18 selected rows and their predicates.
- `src/checks/automation/proof.tst_automationediting.txt` — only the six selected rows and their predicates.

Production edits are limited to a RED-exposed transaction divergence; do not
rewrite correct code merely to make this a production diff. No hot file in
sprint-3 §8 is owned. In particular, do not edit `EditorCommandRouter.swift`,
`DocumentSession.swift`, `tst_EditorDrawer.qml`, or the velocity files.

# Prerequisites

The split and ledger-path repair in sprint-3 §8 are settled. This task consumes
only the existing document/session/page and playback interfaces. It has no
new interface dependency on tasks 80–82 or task 78; it is Group A parallel work.

# Interface contract

- Preserve `releasePlot(x:y:modifiers:) -> Bool`,
  `AutomationNodeResolver.moves(_:) -> AutomationDocumentPlan?`,
  `deletions(revision:_:) -> AutomationDocumentPlan?`, and
  `consumeSelectionCommand(command:) -> Bool`. The page remains the gesture
  owner and `DocumentSession.timeline` the playback authority. No new bridge API.
- Extend the existing fixture with actual LFO-speed events and check-only
  readers of `session.timeline.events` (type `0xB`, track, controller, tick,
  ordered data1 values) and `tempoMap` (tick, exact microseconds and BPM).
  These readers inspect outputs; they must not rebuild an expected timeline
  using the same production algorithm or fall back to document lane reads.
- One literal message anchor per clause. Use distinct messages for the
  selected row groups: A015/A039 held-state immutability; A020/A055 exact
  moved Tempo playback; A041/A081 one dirty/edit publication; A052 translated
  interval and scope; A053/A054 ordered Pan/LFO playback; A061/A067 undo/redo
  Pan playback; A075 selected LFO coverage; A088/A089/A099 absent deleted
  playback events; A095 restored exact Tempo; A116/A117 cancellation selection
  and original playback. The six CC rows each receive their own commit,
  undo, or redo dragged/independent-event predicate.
- Preserve all existing messages, including “selected drag moves the grabbed
  lane”, “selected drag resolves a disjoint CC snapshot”, “one undo restores
  all selected lanes”, “the prompt opens” and “the prompt commits”. Do not
  relabel these as new horizontal-drag evidence.
- Preservation: unrelated Volume, all notes, independent CC points, cursor
  policy, lane scope, same-tick ordering, history atomicity, and held-drag
  document/playback immutability. Empty Delete remains a consumed no-op.

# Implementation steps

1. **RED first:** add the fork-shaped fixture and separate held/commit/undo/
   redo predicates before changing production. Include Tempo 499999 us,
   duplicate same-tick Pan values, LFO and an unselected Volume control.
   A baseline already green proves existing behavior; record it honestly.
2. Drive horizontal selected movement with the existing pointer API and its
   published drag threshold. Split press/move/release so the held snapshot
   and publication counts are observed before release. Fix only demonstrated
   plan/commit/range-shift defects in the named production owners.
3. Exercise selected Delete, undo/redo, empty Delete, and document-rebuild
   cancellation in independent real fixtures. Read the session timeline after
   each completed state transition, never a stale captured projection.
4. Add the separate CC drag at 48 with independent point 96 to the existing
   editing check entry. Do not replace the existing prompt journey. Add a
   mounted ShellGridInput journey that opens Automation, moves a written node,
   selects a range, delivers Delete and Undo through the production keys, and
   observes the visible moved/restored nodes and unchanged roll notes.
5. Run the acceptance lanes after the write group settles; attach only the
   executed message anchors to these rows in the same surface change.

# Acceptance predicate

Controller-run on the settled built tree, each invocation capped at 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — exact
  selected transaction, raw Tempo, independent-event, playback and history
  predicates; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shell-grid-input --verbose` — real mounted
  Automation pointer/selection/Delete/Undo smoke plus existing roll input
  regressions; `build/proof-evidence/shell-grid-input.json`.

Registration is `SessionChecks.swift:82-84`,
`src/checks/checkcatalog.cpp:107-125`, and
`src/checks/editorqml/ShellQmlTests.swift:62-63`. The evidence writer is
`tools/run_checks.ts:426-434`. The first lane does not prove QML delivery;
the second is required even if every Swift predicate passes.

# Task-specific constraints

Incorporate all **Wave constraints and verification policy in sprint-3 §8**:
Swift 6.4/borrowed and fixed-size storage where appropriate, no hot-path
allocations, at-most-two-line comments, base-font sizing, WCAG AA, the sole
window dispatcher and bare-Space rule, one clause/message, real fixtures,
no test seams, no coalescing/idempotence workaround, user approval for any
workaround, deferred menu rows and parked areas unchanged. No new C++.

This is not permission for a general projection-cache refactor or a sweep of
all automation ledgers. No native geometry, focus-pointer or raster rows retire.
The ledgers are the same-commit surface documentation, not a standalone pass.

# Controller verification

After the two lanes have fresh evidence, run `deno task proof check --executed`.
Then run, separately:

- `deno task proof sites --area automation --status PARTIAL`
- `deno task proof sites --area automation --status GAP`
- `deno task proof sites automation/proof.automationselection.txt --status PARTIAL`
- `deno task proof sites automation/proof.tst_automationediting.txt --status PARTIAL`

Only the listed 24 rows are expected to move to MATCHED; no ledger is deleted.
Confirm each compound fork clause has all its constituent messages, especially
raw Tempo (not rounded BPM alone) and the independent CC point. Any unexecuted
clause remains PARTIAL with its precise residual condition.
