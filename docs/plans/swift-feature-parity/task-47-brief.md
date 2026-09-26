# Context

ED07 automation point-menu remainder (task 47). Surface: the mounted automation
drawer's node point menu, its value prompt and lane-delete confirmation — the
presenter `AutomationPage` plus the production drawer QML. This closes the four
deferral themes task 21 left in `src/checks/automation/proof.automationpointmenus.txt`
(second-track fixture, cross-surface invalidation, raster lane, two-point CC) and
leaves the foreign-menu and time-menu-fallback rows named as blocked. Fork oracle:
`git show f3069ef693542bdb63564b80a29773e2f5b2a360:src/checks/automation/automationpointmenus.cpp`
(the ledger's pinned reference revision; byte-identical file is at fork-main
`fceecd88`). Current ledger state: 28 GAP + 15 PARTIAL; this task's commit closes
14 named rows and conditionally 3 more; the rest stay open with recorded blockers.

1. **Second-track fixture — no fixture file needed** (A041/A047–A049 PARTIAL).
   The fork stages its second track at runtime, not from a fixture:
   `addTrack(0) == 1`, `addLanePoint(1, kController, kPointTick, kPointValue)`
   (cpp:221–226), then `songTab.view().selectTrack(1)` inside the prompt-closed
   callback (cpp:241–249); the consumed prompt must not follow the switch — no
   SMF byte, revision or undo change (A050–A053 already MATCHED), the rows swap
   to track B (A048) and track A's row disappears (A049). Swift has every seam:
   `SongDocument.addTrack(voice:) -> Int?` appends a channel chunk and returns
   the new engine-track index (`src/swift/core/EventEditing.swift:43-59`);
   `document.writeLane(track:lane:from:through:points:)` is the family's staging
   API (used verbatim in the stale scenarios,
   `automationpointmenus.swift:135-136,253-254`); `session.selectedTrack`'
   `didSet` publishes `.selection` (`DocumentSession.swift:69-77`) and the
   family fixture already refreshes the page on `.selection`
   (`AutomationPageChecks.swift:156-163`). Current behavior: the prompt cancels
   on a track switch — `refreshFromDocument`'s `stale()` drops a prompt whose
   frozen track ≠ `activeTrack()` (`AutomationPage.swift:455-462`) — and the
   catalog rebuilds for the selected track (`AutomationCatalog.parameters
   (track:)`, `AutomationPage.swift:302-304`). So the rows are open only because
   no Swift scenario stages a second track; the fix is predicates + staging,
   plus one production clause (¶2). **Constraint honored vacuously: no new
   fixture file is created; nothing is copied from decomp projects. If a binary
   fixture ever became necessary, only files already checked in under
   `src/checks/fixtures/` are eligible — never a copy out of a decomp tree.**
2. **Cross-surface invalidation — one production clause + predicates**
   (A073 PARTIAL, A074 GAP, A081/A087/A088 PARTIAL). Fork law
   (cpp:344–401): a selection transition (`selectionModel().setTimeSelection`)
   retires the open point menu through SongView's context-menu seam — menu
   closed, no replacement popup, zero document/history mutation — while the
   *independent* node-value prompt (A081) and lane-delete confirmation
   (A087/A088) survive it untouched; the confirmation's own Cancel still
   resolves it without a write. After task 38a (landed, `7729d961`+): the
   session owns `timeSelection`/`applyTimeSelection(_:)` (equal values publish
   nothing, `DocumentSession.swift:198-237`), `AutomationPage.selection` is a
   forwarder (`AutomationPage.swift:91`), and production dispatches `.selection`
   to `automationPage.refreshFromDocument()` (`DocumentWorkspace.swift:310,355-358`).
   Gap: `refreshFromDocument` retires an open menu only on revision/track/
   parameter staleness (`AutomationPage.swift:464-468`) — a pure selection
   transition leaves it open (A073). The prompt/confirmation sparing already
   holds structurally (`stale()` ignores selection identity) but is unproven.
3. **Raster lane A096 (GAP)** — fork clause `QTRY_VERIFY(!laneBody(volume)
   .isEmpty())` (cpp:426): right after activating the synthetic-default volume
   parameter and before any menu interaction, the rendered lane body is
   non-empty although `lanePoints` is empty (cpp:427). The drawer lane already
   proves exactly this with a real drawn marker — `verify(projectedIndex >= 0,
   "the unwritten lane projects its engine-default node")` over
   `automationLaneNodes()` (drawn node items, `tst_EditorDrawer.qml:5677-5685`,
   helper :3720-3729) inside `test_productionAutomationSyntheticDefaultMenuRoute`
   — but that message was never recorded as an S anchor, so the row reads GAP.
   Closure is ledger-side: record the existing executed message as an S entry
   and map A096 to it. No code change.
4. **Rendered Cancel button (A089 PARTIAL)** — fork clause
   `clickPromptButton(*laneDelete.session, "cancelButton")` (cpp:396). The
   production prompt renders `objectName: "automationPromptCancel"`
   (`AutomationPrompt.qml:163-171`); the drawer lane currently clicks only the
   rendered *accept* button (`tst_EditorDrawer.qml:3800-3803`) and reaches
   Cancel by keyboard Return (:5840-5850). One added interaction: a real mouse
   click on the rendered Cancel button. The sparing rows (A087/A088) close at
   presenter level (¶2); A089's own clause is just the rendered click and its
   closure.
5. **Two-point CC fixture (A216/A219/A220 PARTIAL)** — the fork's switch
   journey asserts the CC lane keeps BOTH pilot points (count 2, second tick,
   second value) across the parameter switch, fresh Tempo prompt and undo
   (cpp:821-825). The Swift `switched` fixture stages one point
   (`automationpointmenus.swift:174` `pan: [(24, 64)]`); the journey's tail
   asserts only that point (:188-189). Fix: stage `pan: [(24, 64), (120, 40)]`
   (the family's standard two-point shape, :99-100/:126-127) and add three
   tail predicates. A217/A218 stay MATCHED on S051.
6. **Ledger rows left untouched (named blockers)**: A070/A071 — the
   time-selection fallback menu has no automation-side ingress; the time-menu
   surface owns it (task-38 family ledgers, `proof.timemenu`). A148–A155,
   A170–A177, A192–A194, A199, A201–A204 — the foreign ruler division-menu
   takeover/survival family: staging needs the grid menu publishing over the
   drawer's pending targets through the roll surface (`PianoGrid.openGridMenu`
   exists since 34b but the arbitration journey spans hot files
   `PianoGrid.swift`/`EditorSurface.qml`); queue with the task-46/50
   menu-arbitration work, not this write set. A161/A162/A181 — close by
   re-verification only (¶Constraints): their reasons predate the executed
   S175/S176 anchors.
7. **Lanes**: this ledger's recorded verification is `deno task verify --filter
   swiftcore --verbose` (runs `runAutomationPageChecks` → `runProjectSessionSuite`,
   suite 10) and `deno task verify:qml --verbose` (editorqml-drawer). Both stay
   this task's lanes; the ledger header line is refreshed in this task's commit.

# Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift` — one clause in
  `refreshFromDocument`'s menu staleness (¶2 contract). No other presenter change.
- `src/checks/automation/automationpointmenus.swift` — new entry
  `drawerAutomationTrackSwitchInvalidation`; new entry
  `drawerAutomationSelectionInvalidation`; extend the `switched` fixture in
  `drawerAutomationDuplicatePromptAndParameterSwitch` to two points + three
  tail predicates.
- `src/checks/automation/AutomationPageChecks.swift` — register the two new
  entries in `runAutomationPageChecks` (after `drawerAutomationOutsidePressRetarget`).
- `src/checks/editorqml/tst_EditorDrawer.qml` — the rendered Cancel-button leg
  inside `test_productionAutomationMenusAndLaneCommands`' confirmation block.
- Ledger (controller-delegated ledger agent, this task's commit):
  `src/checks/automation/proof.automationpointmenus.txt`.

No CMake change (all files already compile into existing targets); no QML
production change; no new files. Sizing exception: one behavior family over
5 files with one verification-surface set (one ledger, two lanes) — named for
the dispatch table.

# Prerequisites

- Task 38a accepted **and checkpointed** — it re-edited `AutomationPage.swift`
  (selection forwarder) which this task re-edits; task 47 consumes its
  interfaces `session.timeSelection`, `session.applyTimeSelection(_:)`,
  `session.selectedTrack`, `.selection` publication.
- Task 38b accepted (paste/insert-time laws on `AutomationSelectionCommands.swift`
  untouched here; no file overlap with this write set).
- No hot-file writes (`ShellWindow.qml`, `ApplicationSession.swift`,
  `EditorSurface.qml`, `PianoGrid.swift`, `GridScene.swift`, `GridPalette.swift`
  all untouched) — parallel-safe with tasks 44/45/48.

# Interface contract

- `AutomationPage.refreshFromDocument()` menu staleness becomes: `if let live =
  menu, stale(live.facts) || live.facts.parameter != activeParameter ||
  live.facts.selection != selection { menu = nil; publishMenuRows() }`. The
  comparison reads the session forwarder (`selection == session?.timeSelection`),
  so any real selection transition (time, note-driven co-motion, track scope)
  retires an open point or lane menu; equal-value applies publish nothing
  (38a law) and retire nothing. Prompts are untouched by selection identity:
  `prompt`/`laneDelete` cancel only on the existing revision/track staleness —
  a selection transition never cancels them (A081/A087/A088 are load-bearing
  on this half; do not widen `stale()`).
- New swiftcore predicates (message-anchored, one per fork clause):
  - `drawerAutomationTrackSwitchInvalidation`, cppID
    `automation/AutomationEditingTest::consumedValuePromptCannotFollowTrackSwitch`:
    "the second track stages its own lane point" (`addTrack(voice: 0) == 1`,
    one written pan point on track 1), "a prompt opens on the first track's
    node", "switching tracks closes the open CC prompt", "the switched page
    lists the second track's pan lane" (`page.catalogIndex(of:
    .controlChange(track: 1, controller: TimeDefaults.ccPan)) >= 0`), "the
    switched page drops the first track's pan lane" (`catalogIndex(of:
    .controlChange(track: 0, controller: TimeDefaults.ccPan)) == -1`), "the
    dropped prompt's late acceptance writes nothing" (`acceptPrompt` returns
    false; `DocumentSnapshot` equality around the switch).
  - `drawerAutomationSelectionInvalidation`, cppID
    `automation/AutomationEditingTest::outsideRightClickDismissesPointMenu`:
    staged on the two-point pan fixture with a lanes-scope selection applied
    through `session.applyTimeSelection(AutomationTimeSelection(range:
    TimeRange(startTick:endTick:), scope: .lanes, lanes: [<pan>], tempo:
    false))`: "a selection change dismisses the owned point menu" (right-press
    menu open → apply → `!page.menuOpen`), "the selection-dismissed menu leaves
    no prompt open" (`!page.menuOpen && !page.hasPrompt`), "a selection change
    spares the open value prompt" (`openPrompt` → apply → `page.hasPrompt`),
    "a selection change spares the lane-delete confirmation"
    (`openParameterMenu` + `deleteLaneEvents` row → apply → confirmation open),
    "the spared confirmation keeps its delete content"
    (`promptKind == AutomationPromptKind.confirmLaneDelete.rawValue`), each
    journey pinned by a `DocumentSnapshot` equality proving zero write.
  - Extended `switched` journey (cppID `…parameterSwitchInvalidatesValuePrompt`):
    "the switch journey leaves two CC points"
    (`lanePoints(panLane).count == 2`), "the second CC point keeps its tick"
    (`points[1].tick == 120`), "the second CC point keeps its value"
    (`points[1].value == 40`).
- New drawer-lane predicate: in `test_productionAutomationMenusAndLaneCommands`,
  after the Return-cancel leg, re-open the confirmation (lane menu row 6) and
  `mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)` —
  message "the confirmation's rendered Cancel button closes it" plus preserved
  event count and unchanged revision (existing assertion style :5843-5850).
- Preservation contract: existing S-anchor predicates and their messages are
  unchanged; the four drawer cases stay green; prompt staleness on
  revision/track/parameter identity is unchanged; `AutomationMenuAction` ids,
  menu rows, prompt kinds and objectNames are unchanged.

# Implementation steps

1. RED: add the `drawerAutomationSelectionInvalidation` predicates first; the
   menu-dismissal messages must fail against the current presenter (menu stays
   open on a pure selection change). Record RED.
2. Add the `refreshFromDocument` menu clause (¶Interface contract). Re-run:
   the RED predicates go GREEN; the sparing predicates and every existing
   automation suite stay green.
3. Add `drawerAutomationTrackSwitchInvalidation`: stage `addTrack(voice: 0)`,
   `writeLane(track: 1, …)` pan point, snapshot, activate track 0's pan,
   `openPrompt(tick: 24, value: 64)`, `session.selectedTrack = 1`, assert the
   contract's five predicates. If any fails, the fixture's `.selection`
   refresh path is broken — fix the path, never the predicate.
4. Extend the `switched` fixture to `pan: [(24, 64), (120, 40)]` and add the
   three tail predicates after the existing "the CC lane stays untouched".
5. Add the drawer-lane rendered-Cancel leg.
6. Run the lanes below; report GREEN with predicate messages and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — new track-switch and
  selection-invalidation predicates, extended two-point switch journey, all
  existing `runAutomationPageChecks` suites (prompt transactions, delete/stale,
  duplicate/switch, lane-delete confirmation, outside-press retarget).
- `deno task verify:qml --verbose` — editorqml-drawer: the four production
  automation cases incl. the rendered-Cancel leg and the A096 anchor message.
- Expected RED→GREEN: only the selection-dismissal predicates (step 1→2).
  Every other new predicate pins standing behavior; a RED there is a
  discovered gap — fix per contract before GREEN.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants; no new fixture files; never copy anything out of a decomp
  project (staging is `addTrack` + `writeLane` on the in-memory fixture,
  fork-identical).
- One message-anchored predicate per fork clause; exact messages as listed —
  the ledger agent adds S rows with them, flips Dispositions, and refreshes
  the ledger's stale `Verification:` header to this brief's lanes.
- Implementers never edit ledgers; the controller delegates
  `proof.automationpointmenus.txt` to the ledger agent in this task's commit:
  - A041 → "the second track stages its own lane point"; A047 → "switching
    tracks closes the open CC prompt"; A048 → "the switched page lists the
    second track's pan lane"; A049 → "the switched page drops the first
    track's pan lane" (late-acceptance no-write noted on the existing
    A050–A053 anchors).
  - A073 → "a selection change dismisses the owned point menu"; A074 → "the
    selection-dismissed menu leaves no prompt open"; A081 → "a selection
    change spares the open value prompt"; A087 → "a selection change spares
    the lane-delete confirmation"; A088 → "the spared confirmation keeps its
    delete content"; A089 → "the confirmation's rendered Cancel button closes
    it" (drawer lane).
  - A096 → S row for the existing executed message "the unwritten lane
    projects its engine-default node" (`tst_EditorDrawer.qml:5685`).
  - A216/A219/A220 → the three two-point tail messages.
  - A161/A162/A181 → re-verify against the executed S175/S176 ("the rejected
    row activation dismisses the stale point menu" / "…opens no prompt") +
    S038; close as MATCHED citing them if the coverage holds at freeze, else
    leave PARTIAL with the reason updated.
  - Rows left open with recorded blockers: A070/A071 (time-menu surface owns
    the fallback ingress), A148–A155/A170–A177/A192–A194/A199/A201–A204
    (foreign ruler division-menu arbitration; queue with tasks 46/50).
- Re-verify each named row's reason against the landed source at freeze —
  several GAP reasons predate tasks 34b/38a and describe seams that now exist.

# Controller verification

After the writer settles and no check processes remain:

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — the ledger shows the 14 new
   MATCHED rows with executing anchors and no unmapped MATCHED sites.
2. Native smoke (desktop): launch the built app, open a song's Automation
   drawer, right-press a written node (menu opens), drag a ruler sweep (menu
   closes; nothing written); re-open and pick Set Value (prompt opens), sweep
   again (prompt stays; Escape drops it without a write); open a lane's
   Delete-automation confirmation, click its rendered Cancel (closes, lane
   intact); switch tracks with a prompt open (prompt drops, catalog swaps, no
   edit lands on the old track).
