# Context

Task 60 — voice-changes page: rendered Insert pick + rendered-row/menu proof. Close the
voice family (93 open rows: `proof.voice.txt` 50 + `proof.voicemenus.txt` 43) on the
mounted surface and delete both ledgers; repair this surface's seven never-executing
ledger anchors. The surface exists and executes: `VoiceChangesPage.swift` +
`src/ui/songview/quick/drawer/VoiceChangesPage.qml` mounted in the drawer lane
(`test_productionVoiceChangesPageMountsAndRenders`, `tst_EditorDrawer.qml:4143`),
presenter predicates under `runVoiceChangesPageChecks`
(`VoiceChangesPageChecks.swift:151`, project-session suite via
`SessionChecks.swift:81`, lane `swiftcore-projectsession` at `checkcatalog.cpp:125`).
Proof completion + one determinism repair, not a rebuild: no production law gap
identified at freeze (¶3).

1. **Census (verified this freeze)**: voice 148 rows = 96 MATCHED, 37 PARTIAL, 13 GAP,
   2 RETIRED → 50 open — `voiceSurfaceAndPaintLifecycle` A001–A053 (20),
   `voiceHoverLifecycle` A055–A058 (4), `voiceRefreshLifecycle` A064–A078 (10),
   `voicePickerTransactions` A080–A122 (7), `voiceMarkerDragTransactions` A131–A142
   (6), `voiceCameraTransactions` A144–A146 (3). voicemenus 84 rows = 32 MATCHED,
   34 PARTIAL, 9 GAP, 9 RETIRED → 43 open — `voiceContextMenuTransactions` A001–A022
   (14), `voiceMenuTargetHoldsAcrossCameraScroll` A033–A046 (13),
   `voiceMenuStaleDocumentRejectsPick` A047–A057 (4),
   `voiceMenuOutsideRightDismissesWithoutRetarget` A058–A066 (5),
   `voiceMenuForeignTakeoverStaysUsable` A067–A078 (7). Fork files are byte-identical
   between the ledgers' Reference `f3069ef6` and oracle `fceecd88` (`git diff
   --stat`, empty).
2. **Fork laws** (`git show f3069ef6:src/checks/drawerpresentation/…`; both deleted in
   `67544720`):
   - `voicemenus.cpp:99-173 voiceContextMenuTransactions` — empty-lane right-press →
     menu; **real click on the rendered Insert row** → shared picker opens, menu
     panel gone; filter `"007"` → row(7) → accept → point value 7, revision+1,
     undoIndex+1. Marker right-press → rendered Change-Voice row → picker preselects
     the captured voice → filter `"003"` → accept → value 3. Rendered Delete row →
     menu closes, exactly the captured point removed (:111–154).
   - `:175-221 …TargetHoldsAcrossCameraScroll` — camera-only scroll keeps the menu
     open; the scrolled rendered Change row still clicks; accept moves **exactly the
     captured marker** to 7, every pre-existing point untouched, one revision + one
     history step (:187–218).
   - `:223-270 …StaleDocumentRejectsPick` — a rewrite between the rendered Delete
     row's press and release voids the activation: menu closed, no popup reopened,
     exactly the rewrite stands (:232–267).
   - `:272-306 …OutsideRightDismisses…` — outside right press dismisses; the paired
     release is swallowed (no popup, no write); the voice band regains focus
     (:284–302).
   - `:308–360 …ForeignTakeoverStaysUsable` — a ruler division menu opening over the
     pending voice menu displaces the target; the foreign menu stays usable (division
     row click changes the grid); the voice target never fires (:318–354).
   - `voice.cpp:102-173 …SurfaceAndPaintLifecycle` — plot x = `timelineSplitX`, input
     bounds = plot size, gutter = fixed span × band height; lane edit → third marker,
     revision+1, undoIndex+1, undo restores, SMF byte-equal; readout transitions at
     span boundaries (:110–137). `captureQuickBand`/`changedPixels` (:146/:154-155)
     are native harness.
   - `:175-240 …HoverLifecycle` — one hover label; preserved across playhead moves
     inside one span; cleared at a change-boundary crossing; leave and Escape clear;
     marker labels invariant (:181–230).
   - `:242–298 …RefreshLifecycle` — track switch re-derives labels; hide hides the
     input, re-show re-derives; symbol-less bank → numeric fallback labels (`"003 "`),
     bank restore returns names; renamed symbol relabels (:247–297).
   - `:300–419 …PickerTransactions` — double-click → picker, search focus, preselect;
     unchanged-value accept is a no-op; empty filter disables accept; audition
     hold/release pairs (7, 60, 0); song replacement cancels the picker without
     writing and a re-attach drives a fresh insertion; undo/redo round-trip
     (:306–418).
   - `:421–455 …MarkerDragTransactions` — Escape mid-drag commits nothing; commit =
     one revision + one undoIndex; undo restores bytes and index; redo restores
     (:426–454). `:457–490 …CameraTransactions` — wheel zooms anchored (display
     stability ≤ 1 px); middle-drag pan clamps at the scroll floor (:460–483).
3. **Swift current state — no production law gap at freeze**: the rendered surfaces
   exist — `VoiceChangeMenu.qml` (QuickMenuPanel, rows `voiceMenuRow_`, activation →
   `model.activateMenuRow`, :36,55-59), `VoicePicker.qml` (modal `voicePicker`,
   search field, ListView rows `voicePickerRow_`), mounted helpers
   (`tst_EditorDrawer.qml:3960–4136`). Menu rows for an empty target publish only
   Insert; a marker target publishes Change Voice + Delete
   (`VoiceChangesProjection.swift:484-489`). The plot already delivers camera input:
   `WheelHandler` → `gridModel.handleWheel` anchored (`VoiceChangesPage.qml:475-486`),
   middle-press pan → `session.mutateCamera { $0.setHScroll(…) }`
   (`VoiceChangesInteraction.swift:81-85,137-143`), `dispatchEscape` owns picker/menu/
   drag/pan/hover (:29-37). Hover/drag/pan state is page-owned and survives
   projection rebuilds (`reuseGeometry: true`, `VoiceChangesPublication.swift:98-109`);
   `refreshPlayhead` republishes only the readout inside one span
   (`VoiceChangesPage.swift:393-397`); `contentBuildCount`/
   `playheadPresentationCount` expose rebuild counts; history depth is public
   (`document.history.undoIndex`/`undoCount`). Checks are presenter-level
   (`voice_projection/voice_picker/voice_interaction/voice_lifecycle/voicemenus.swift`)
   plus seven mounted production tests (`tst_EditorDrawer.qml:4143,4200,4299,4396,
   4439,4512,4630`); the mounted menu test clicks only the rendered Delete row today.
   **No used-mark UI exists anywhere in this surface** (fork + Swift verified); the
   sprint's "used-mark transition" maps to the in-use readout/hover context
   transitions (voice A017, A042–A046) and held-span re-derivation — the rows this
   brief closes.
4. **Never-executing anchors — root cause and fix (all seven)**: `proof check
   --executed` resolves a message anchor by scanning evidence pass rows for the
   literal string (`tools/proof_reader.ts:574-580`); it does no call-graph analysis.
   All four distinct messages sit on conditionals the staged project bank never
   takes: S044/S046 "the staged bank publishes no blank slot to drive"
   (`voice_projection.swift:263`, guard else-branch — the staged bank always HAS a
   blank slot), S263/S270 "…to commit" (`voice_picker.swift:372`, same shape), and
   S187/S194 + S188/S195 "a name filter keeps the slot that carries it" / "every row
   matched by name really carries the name" (`voice_picker.swift:352-361`, skipped
   because `programs[0]`'s parsed voice carries an empty symbol). No A-row cites any
   of the seven; they are S-index orphans. Fix within the surface (steps 1–2): the
   name-filter pair becomes deterministic and always executes with its messages
   verbatim; the two no-blank-slot guard emissions convert to `report.fail` staging
   contracts (the sanctioned guard shape), and the ledger agent re-anchors their four
   S entries to `Anchor: function` (precedent: voice S156).
5. **Task boundary**: task 54 finisher owns uncommitted `tst_EditorDrawer.qml` edits;
   59b (drawer velocity ink) is queued after it; 56/57 may also precede this task in
   the serial `tst_EditorDrawer.qml` chain (sprint §5). This task touches no hot
   production file — `voicechanges/*` and the drawer QML are unlisted. Ruler
   division-menu rows of the foreign-takeover function belong to the ruler lane
   (task-53's mounted grid-menu rows); cross-lane mapping per task-59 precedent,
   flagged below. `proof.automationvoice.txt` stays open (31 rows, automation
   long-tail backlog); this task only re-anchors its four S entries.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawer.qml` — new test functions (rendered
  Insert/Change-Voice row picks with picker accept; camera-scrolled menu hold;
  outside-right paired release + focus restore; Escape mid-drag; wheel-anchored zoom
  + middle-drag pan floor; plot/gutter geometry) and extensions to
  `test_productionVoiceChangesPointerAndMenuTransactions` /
  `test_productionVoiceChangesPageMountsAndRenders`. Shared file — see Prerequisites.
- `src/checks/drawerpresentation/voice_picker.swift` — deterministic named-slot
  selection for the name-filter pair (S187/S188 execute, messages verbatim);
  `drawerVoiceBlankSlotCommit` guard → `report.fail`; detach/re-attach predicate
  (A121/A122); undoIndex anchor (A087).
- `src/checks/drawerpresentation/voice_projection.swift` — `drawerVoiceSlotLabels`
  guard → `report.fail` (S044/S046).
- `src/checks/drawerpresentation/voice_lifecycle.swift` — hover context-transition
  predicate (survive-within-span, clear-at-boundary, leave, Escape); hide/show +
  bank re-attach refresh predicate (numeric fallback, restore, rename).
- `src/checks/drawerpresentation/voice_interaction.swift` — drag history/revision
  anchors (undoIndex before/after commit, undo restore, redo restore).
- `src/checks/drawerpresentation/voicemenus.swift` — camera-scroll point-survival
  matrix; stale-rewrite outcomes (rewrite stands, marker keeps its voice). Delete the
  stale header comment at :5-6 while editing.
- `src/checks/drawerpresentation/VoiceChangesPageChecks.swift` — call sites for new
  predicate functions; staging guard extended to require one named editable slot.
- Contingent only (edit solely to fix a divergence a new predicate exposes):
  `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift`,
  `VoiceChangesInteraction.swift`, `src/ui/songview/quick/drawer/
  VoiceChangesPage.qml`, `VoiceChangeMenu.qml`, `VoicePicker.qml`.
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip then
  delete `src/checks/drawerpresentation/proof.voice.txt` and
  `proof.voicemenus.txt`; re-anchor S044/S046/S263/S270 to `Anchor: function` in
  `src/checks/automation/proof.automationvoice.txt` (no A-row changes there).

No CMake changes (no new files), no rollcheck/velocity/automation files, no
`ShellWindow.qml`/`EditorSurface.qml`/`PianoGrid.swift`. Sizing exception: one
behavior family's proof completion over 7 check files + ledgers, two lanes — named
for the dispatch table.

# Prerequisites

Task 54 finisher and 59b settled (both own `tst_EditorDrawer.qml`; sprint §5 serial
chain 55 → 56 → 57 → 59 → 60), and 56/57 checkpointed if dispatched first.
Re-snapshot the `tst_EditorDrawer.qml` line cites (uncommitted 54 edits already move
them). Nothing consumed from 52/53/61/64.

# Interface contract

No production interface changes. New check-side behavior:
- `drawerVoicePickerKeyboardPolicy` selects its filter name from the first staged
  slot with a non-empty symbol (not unconditional `programs[0]`); the two existing
  messages stay verbatim and now execute every run.
- `drawerVoiceSlotLabels` / `drawerVoiceBlankSlotCommit` guards call
  `report.fail(drawerVoiceLabelID/drawerVoiceCollisionID, "the staged bank publishes
  no blank slot to drive/commit")` when staging lacks a blank slot — loud staging
  contract, matching the suite-entry guard (`VoiceChangesPageChecks.swift:154-158`).
- `runVoiceChangesPageChecks` staging guard additionally requires one editable slot
  with a non-empty symbol (fail message names the count, same shape as the existing
  one).
- New presenter predicates (message-anchored, one per fork clause family; existing
  S-inventory messages stay verbatim): "hover survives a playhead move inside one
  voice span"; "a playhead crossing the change boundary clears the hover context";
  "a pointer leave clears the hover"; "an escape clears the hover"; "hiding the
  section cancels the interaction and clears the hover"; "re-showing the section
  re-derives the markers"; "a bank without symbol names falls back to program-number
  labels"; "restoring the bank restores the named labels"; "a renamed voice symbol
  relabels the lane"; "a detached page cancels its open picker without writing"; "a
  re-attached page drives a fresh insertion"; "the committed insertion advances the
  undo index by one"; "the committed drag advances the undo index by one"; "undo
  restores the drag's bytes and index"; "redo restores the committed drag"; "the
  post-scroll change pick moves exactly the captured marker"; "every pre-existing
  point stands untouched across the pick"; "the pick lands as one revision and one
  history entry"; "a rewrite between press and release voids the activation"; "the
  rewrite stands as the only change".
- New mounted test functions (QML evidence records function names; one per journey):
  `test_productionVoiceChangesInsertAndChangeRowPicks`,
  `test_productionVoiceChangesMenuHoldAcrossCameraScroll`,
  `test_productionVoiceChangesDismissalAndEscape`,
  `test_productionVoiceChangesCameraTransactions`. Existing voice test function
  names stay verbatim (ledger-cited).
- Bank re-attach drives the production path (`page.detach()` + attach of a fixture
  session built from a symbol-less/renamed slot view — the `toneSlots` construction
  precedent, `voice_projection.swift:185-203`), never a new seam.

# Implementation steps

1. Determinism repair (¶4): named-slot selection in `drawerVoicePickerKeyboardPolicy`;
   guard conversions; staging-guard extension. Expected GREEN with S187/S188/S194/S195
   now appearing in the lane evidence.
2. Presenter predicates (proof, not fix — expected to pass immediately; a failure
   exposes a real divergence, fix in the contingent files and record RED→GREEN for
   that fix only): hover transitions over the existing fixture (playhead moves via
   the page's playhead fan-out, leave/Escape via dispatch); hide/show through the
   drawer presenter's section visibility ingress (task-52 `setSectionBodyHeight`
   neighborhood); bank re-attach refresh; detach/re-attach; history/revision anchors
   on the existing drag and insertion scenarios; scroll point-survival and
   stale-rewrite matrices on the existing menu fixture.
3. Mounted predicates: rendered Insert row pick through the real menu and picker row
   delegates; Change Voice pick with preselect; real wheel over the plot input, then
   a scrolled rendered Change-row click; outside-right press + swallowed paired
   release with plot-input focus restore; Escape mid-drag; wheel zoom anchored
   (pxPerBeat up, anchored tick's display x stable ≤ 1 px) and middle-drag pan
   clamped at the camera floor; plot x = gutter split, input bounds = plot size,
   gutter = fixed span × band height.
4. Run the lanes below; the evidence JSONs (`build/proof-evidence/
   swiftcore-projectsession.json`, the qml lane's) feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore-projectsession --verbose` — all voice
  predicates incl. the repaired anchors (S187/S188 messages present in output) plus
  session-suite regressions.
- `deno task verify:qml --verbose` — drawer lane: existing voice functions (54/59b
  re-anchors stay green), the four new functions, full drawer regression.
- Runtime prerequisite: the drawer lane's usual offscreen-capable Qt windowing; no
  native audio.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions
  (`voicemenus.swift:5-6`); no pixel constants in production (1-px anchor tolerance
  and fixture ticks are check-side).
- One message-anchored predicate per fork clause; ledger-cited messages verbatim.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify at freeze against
  the evidence JSONs and `git show f3069ef6:…`):
  - voice: A023/A027/A028/A034/A040/A041/A072/A076/A077 → `RETIRED-REPRESENTATION`
    (native `captureQuickBand`/`changedPixels` framebuffer harness; sprint §4;
    pinned `f3069ef6`). A001/A002/A004/A005/A006/A007 → mounted geometry anchors.
    A017 → lane-edit revision/undoIndex + readout-transition anchors. A042/A043/
    A044/A046/A049/A053 → hover-transition anchors (A049's label-invariance rides
    the same function). A055–A058/A064/A065 → hide/show anchors. A068/A069/A071/
    A074/A078 → bank re-attach anchors. A080 → mounted picker-focus observation
    (existing `awaitVoicePickerFocus` evidence). A087 → undoIndex anchor. A097 →
    `RETIRED-REPRESENTATION` (pins the native `QSignalSpy` connection; the count
    clauses are the existing audition anchors). A099/A109 → mounted rendered-row
    press anchors. A121/A122 → detach/re-attach anchors. A131 → mounted Escape
    anchor. A135/A138/A139/A141/A142 → drag history anchors. A144/A145/A146 →
    mounted camera-transaction anchors. Delete the file when all 148 rows are
    MATCHED/RETIRED.
  - voicemenus: A001–A006/A011–A016/A021–A022 → the rendered pick functions'
    anchors (insert, change, delete sequences; the native QuickPopupSession half is
    the rendered panel/row observation). A033/A035–A040 → mounted menu-hold
    function; A041–A046 → the scroll point-survival anchors. A047 → mounted
    menu-open; A049 → rendered Delete-row geometry observation; A056/A057 →
    stale-rewrite anchors. A058/A060/A063/A066 → mounted dismissal/focus anchors;
    A059 → `RETIRED-REPRESENTATION` (native focused-band polling). A067 → mounted
    menu-open anchor; A071/A078 → `RETIRED-REPRESENTATION` with the lane-named
    reason (ruler item-graph/focus internals); A074–A077 → the ruler lane's executed
    grid-menu anchors (task-53, `tst_ShellGridMenu`) if they cover division-row
    clicks at freeze, else the same lane-named retirement — controller-flagged,
    never re-open that lane here. Delete the file when all 84 rows are
    MATCHED/RETIRED.
  - automationvoice: re-anchor S046/S194/S195/S270 to `Anchor: function`
    (S156-precedent); no A-row changes; ledger NOT deleted.
- The stale `voice.cpp`-side PARTIAL reasons citing "no public bankSlots mutation
  API" (A068/A069/A074) close via the production detach/attach path above — the real
  bank-replacement route the drawer uses, no new session mutation API.
- WCAG AA beats parity if a rendered-row contrast expectation fails: fix the palette
  role, not the check.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof check
   --executed` (pre-deletion state shows both ledgers fully closed and the seven
   repaired anchors executing — the global not-executed count drops by seven), then
   `deno task proof sites --area drawerpresentation` reports no voice/voicemenus
   ledger files (drawer.txt/valueprompt.txt/velocity.txt remain — other tasks').
2. Visual/native smoke (desktop): right-press an empty voice-lane spot → Insert row →
   pick a voice in the rendered picker → the marker appears and the readout names it;
   right-press a marker → Change Voice → preselected picker accepts; scroll the
   editor with the menu open → the menu stays and its rows still click; press outside
   right → menu dismisses and the plot regains focus; wheel over the band zooms
   anchored; middle-drag pans and clamps at the pre-roll floor; Escape mid-drag
   changes nothing.
