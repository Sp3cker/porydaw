# Context

Pencil velocity latch + Set Velocity round-trip + note-menu retarget (task 54). One
surface: the mounted roll's velocity latching, its Set Velocity prompt as a roll-surface
session, and the note context menu's open/retarget/invalidation laws. Closes the three
rollcheck ledgers (`pencil_velocity` 39 open of 53, `velocity_prompt` 44 of 105,
`pencil` 10 of 22). Fork oracle `fceecd88`; write sets re-snapshot after tasks
41b/50a/52/53 settle.

1. **Fork latch laws** (`pianoroll_gestures.cpp`, `pianoroll_gestures_active.cpp`,
   `pianoroll_commands.cpp`): `m_lastVelocity = 100` default (`pianoroll.h:371`); any
   left press on a note latches its velocity — plain press (:145) and velocity-drag
   anchor press (:199); a committed Ctrl-drag latches anchor+delta (`_active.cpp:301`);
   Set Velocity acceptance latches (`pianoroll_commands.cpp:707`); draws commit with
   the latch (`_active.cpp:246`). Gutter law (`pianoroll_gestures.cpp:65-69`,
   `pianoroll_interaction.cpp:228-234`): a keyboard-gutter press selects every
   primary-track note on that key (`setNoteSelection(notesOnKey(key))`) and auditions
   at literal **100**; glissando re-auditions at 100 without reselecting.
   Current Swift: latch laws **already exist** — `PianoGrid.swift:131`
   (`lastVelocity = 100`), `:624` (press latch), `:1042` (drag-commit latch),
   `:1071` (draw uses latch), prompt relatch via `DocumentWorkspace.swift:130-135`.
   The ledger reasons "pointer draws always use the fixture latch (velocity 100)"
   are stale preamble — predicates are missing, not the feature. The gutter is
   genuinely unported: `updateKeyboardPointer` (`PianoGrid.swift:918-928`) auditions
   with `lastVelocity` (fork: literal 100) and never selects.
2. **Fork prompt laws** (`velocity_prompt.cpp`, `quick/VelocityPrompt.qml`,
   `quick/DragInput.qml`, `pianoroll_commands.cpp:620-660`): two entries — the
   note-menu row and the selected-note entry (empty selection ⇒ no prompt, no write);
   the form opens centered on the canvas with the initial literal selected; typing
   never writes; OK/Enter commits exactly one undo entry and returns focus to the
   **roll**; unchanged acceptance writes nothing but relatches; Escape/Cancel/outside
   press close write-free, swallow the paired release, and refocus the roll; a stale
   document closes on accept without overwriting the foreign edit; Tab cycles
   input→OK→Cancel; PageUp/PageDown step 10, arrows step 1 (Ctrl ×10), clamped 1/127;
   Current Swift: transaction state is complete and proven at presenter level
   (`VelocityInteraction.swift:243-309`: capture/revision/track guards, stale
   reject, one-entry commit; `velocity_prompt.swift` seeds 73 with bytes/history
   asserts) and rendered in `tst_EditorDrawer.qml` (S059–S062: Tab cycle, clamps,
   outside dismissal, Escape/Cancel/Enter, focus). Divergences: the card lives in
   the drawer's `modalLayer` (`VelocityPage.qml:488-498`,
   `EditorDrawer.qml:498-506` — `visible: drawerScope.visible`, so the prompt is
   **invisible when the drawer is hidden** while `promptOpen` is true); focus
   returns to the drawer's velocity plot (`focusOrigin()` `VelocityPage.qml:500-504`)
   instead of the roll; the mounted fixture never asserts literal 73 (A004/A005
   PARTIAL); no afterDraw baseline around the unchanged acceptance (A018); no
   mounted no-op-accept or bytes/history asserts (A047/A070/A072/A103 PARTIAL).
3. **Fork note-menu laws** (`pianoroll_commands.cpp:536-600`, `pianoroll.cpp:61-75`,
   `pianoroll_gestures_active.cpp:195-210`): right release over a note selects it if
   unselected, then opens the menu at the release point (empty selection ⇒ no menu);
   `QuickMenuHost.outsideRightPressed` forwards an outside right **press** to
   `retargetNoteMenu` → `focusNoteUnderCursor` + `showNoteMenu` — the menu reopens for
   the note under the cursor on the press, the paired release is swallowed (no
   timeline mutation); an outside right press on an empty row dismisses the menu
   (release swallowed, selection preserved, no write); `contextMenusInvalidated`
   (selection, document edit, rebinding) retires the open menu synchronously; row
   activation runs canonical actions — Set Velocity opens the form as the follow-on
   session, other rows restore roll focus.
   Current Swift: the menu is `shellGridContextMenu` (`ShellWindow.qml:883-905`),
   opened on `endRightPointer` → `contextMenuRequested` (`PianoGrid.swift:848-851`) →
   `contextMenuAt` (`ShellWindow.qml:613-618`) — **without** the select-if-unselected
   law (right-clicking an unselected note opens a menu whose Set Velocity row then
   no-ops: `NoteCommands.isAvailable(.setVelocity)` gates on selection and the prompt
   captures the live selection). No outside-right retarget, no dismiss-on-edit, no
   empty-space dismiss forward (a `Basic.Menu` consumes outside presses without
   forwarding). `focusNoteUnderCursor` already exists from task-41b
   (`PianoGrid.swift:602-607`) and is the retarget primitive.
4. **Stale-preamble adjudication**: `pencil.swift` already executes
   `checkPencilFractionalPlacement` with the guard message `"no empty fractional
   displayed cell for edit regression"` (`pencil.swift:101-136`) and the
   default-velocity-100 draw (`:154-155`); `velocity_prompt.swift:16` executes
   `"the synthetic fixture published fewer than three notes"`. Seed-guard/epilogue GAP
   rows citing "no executing predicate" predate these and re-anchor in this task's
   commit without new code. The remaining `NATIVE: prompt-window delivery` rows
   observe the rendered form's delivery (buttons, keys, focus, reopen) — provable
   in-scene like the MATCHED S059–S062 rows; only rows pinning the popup's native
   window/frame identity retire.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`* — right-release select law; `retargetNoteMenu`;
  gutter press selection + literal-100 audition.
- `src/swift/app/ApplicationSession.swift`* — `velocityPagePresenter()` accessor
  (pattern :406-484).
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — `VelocityPrompt` loader over
  the roll (the `insertTimePromptLoader`/`pitchBendPopupLoader` precedent :968-1056);
  close-focus to `rollInput`.
- `src/ui/songview/quick/VelocityPrompt.qml` — host-supplied focus origin; palette
  from the grid palette (no literals).
- `src/ui/songview/quick/drawer/VelocityPage.qml` — delete the `VelocityPrompt`
  instance, its `modalHost` plumbing, and the prompt's `focusOrigin` coupling (the
  page's gesture-only focus-loss law stays; `EditorDrawer.qml`'s `modalHost`
  machinery stays for the voice picker).
- `src/ui/shell/ShellWindow.qml`* — note-menu underlay (outside right press
  retarget/dismiss with swallowed release), close on document-history/tab
  invalidation.
- `src/swift/app/shell/ShellPresenter.swift`* — only if activation plumbing needs it;
  drop at freeze if unchanged (ids/rows already correct :49,95,113).
  `src/swift/app/DocumentWorkspace.swift`* — expected unchanged; touch only if the
  `onSetVelocityRequested` wiring moves with the prompt host.
- Checks: `src/checks/rollcheck/pencil.swift`, `src/checks/rollcheck/velocity_prompt.swift`,
  `src/checks/editorqml/tst_ShellGridMenu.qml`, `src/checks/rollqml/tst_SwiftRollSelection.qml`,
  `src/checks/editorqml/tst_ShellNoteVisuals.qml`, `src/checks/editorqml/tst_EditorDrawer.qml`
  (re-anchor focus/role messages after the remount; transaction messages verbatim).
- Ledgers (controller-delegated ledger agent, this task's commit): `proof.pencil_velocity.txt`,
  `proof.velocity_prompt.txt`, `proof.pencil.txt`.

No C++, no `NoteCommands.swift` (dispatch already correct), no `GridScene.swift`
painting change, no automation/pitch-bend/ruler menu files. Sizing exception: one
behavior family over ~13 files with one verification-surface set.

# Prerequisites

Tasks 41b (settles `PianoGrid.swift`/`EditorSurface.qml`; consumes `focusNoteUnderCursor`
and the popup-loader seam) and 46 (menu topology) landed; 50a settled
(`ShellWindow.qml`); 52/53 landed (EditorSurface/PianoGrid chain 52→53→54).

# Interface contract

- `PianoGrid.endRightPointer(x:y:)` — a pending-menu release hitting a note not
  already selected makes selection `{note}` before `contextMenuRequested` (fork
  `releasePendingMenu`); empty-space release keeps today's clear-both behavior.
- `PianoGrid.retargetNoteMenu(x:y:) -> Bool` — maps a press inside the plot to
  `focusNoteUnderCursor`; on a primary-track hit re-emits `contextMenuRequested` at
  that point and returns true; no hit ⇒ false (caller dismisses). Never mutates the
  document or selection beyond the single-note focus law.
- `PianoGrid.beginKeyboardPointer`/`updateKeyboardPointer` — press selects every
  primary-track note on the pressed key and auditions `(track, key, 100)`; glissando
  re-auditions at 100 without changing selection; `endKeyboardPointer` unchanged;
  `lastVelocity` is never read or written on the gutter path.
- `ApplicationSession.velocityPagePresenter() -> VelocityPage` — the selected
  workspace's velocity page, nil-preserving like the other accessors when no song.
- EditorSurface prompt loader — `active: velocityModel.promptOpen`; full-surface
  underlay cancels on any-button outside press and keeps the pair alive through the
  matching release (the `consumingOutsidePress` law already in `VelocityPrompt.qml`);
  card centered on the surface; Escape/OK/Cancel/outside close returns focus to
  `rollInput`; the prompt renders regardless of drawer section or drawer visibility;
  typography/palette from the grid body role (`promptPalette: gridModel.palette`).
- ShellWindow note menu — opens only through the roll's `contextMenuAt`; while open,
  a right press outside its frame retargets (`retargetNoteMenu`) or dismisses (no
  hit), the paired release never reaches the roll, selection/bytes/history stay
  untouched; left outside press and Escape dismiss; any document-history change or
  tab/song change closes it synchronously (fork `contextMenusInvalidated`; the
  `actionRevision`/`canUndo` seams exist at `ShellWindow.qml:132-134` — bind the
  close to a revision notification that fires on every edit, not only canUndo
  flips).
- Draw/latch semantics unchanged: `lastVelocity` stays `@QtTracked`, default 100,
  press/drag-commit/acceptance writes exactly as today.
- New check anchors (message-anchored, one per fork clause; ledger-cited messages
  stay verbatim except the re-anchors named below):
  - swiftcore `swiftcore/PianoRoll::velocityClickLatch`: "a clicked velocity latches
    into the next drawn note" (seed 73 → click → free-cell draw → 73; undo restores
    bytes), "the click latch draws without touching history beyond the draw".
  - swiftcore `velocityDragCommit` additions: "a committed drag velocity latches into
    the next drawn note" (93); existing preview/status scenarios gain exact undo
    index/count/byte snapshots (A028/A029/A033).
  - swiftcore `velocityPromptAcceptUndoLatch` additions: "an accepted prompt velocity
    latches into the next drawn note" (95), "an unchanged acceptance relatches the
    note's velocity for the next draw" (73, with the oracle's afterDraw baseline:
    draw between the two accepts).
  - swiftcore `swiftcore/PianoRoll::pencilGutterSelection`: "a keyboard key press
    selects every matching note", "the gutter auditions at the fixed velocity 100",
    "gutter selection records no history".
  - swiftcore `pencilPlacement` guards re-anchor to the existing `"no free grid cell
    to draw in"`/`"no empty fractional displayed cell for edit regression"` setups;
    add "the fixture mounts a timeline" for the `QVERIFY(view.timeline())` clause.
  - tst_ShellGridMenu: "a right release over an unselected note selects it and opens
    the note menu", "the rendered note menu leads with Set Velocity and omits Paste",
    "an outside right press retargets the open note menu to the note under the
    cursor", "the retarget release leaves the timeline untouched", "an outside right
    press on an empty row dismisses the note menu without editing", "a document edit
    retires the open note menu synchronously", "the Set Velocity row opens the prompt
    over the roll with the note's velocity selected" (fixture note at 73), "accepting
    an unchanged velocity over the roll writes nothing and relatches the pencil",
    "Escape closes the prompt over the roll without writing", "the prompt renders
    over the roll while the drawer is hidden".
  - tst_SwiftRollSelection: "clicking a note latches its velocity for the next draw"
    (real pointer; readback through the mounted grid's published note data).
  - tst_ShellNoteVisuals: "a drawn note paints its interior in the velocity fill",
    "note color does not escape its border box", "abutting notes leave no unpainted
    gap column" (grabImage sampling, the existing S014 pattern).
  - tst_EditorDrawer re-anchors (intentional behavior change): "outside cancellation
    returns focus to the velocity plot" → "outside cancellation returns focus to the
    roll"; the body-role audit follows the grid body role; all
    transaction/validation/clamp messages stay verbatim.

# Implementation steps

1. RED in swiftcore (`pencil.swift`, `velocity_prompt.swift`): the four latch-draw
   predicates and the gutter trio. The gutter rows stay RED until step 2; the
   latch-draw predicates may pass immediately (laws exist) — record as re-anchoring
   evidence, not behavior change.
2. `PianoGrid`: right-release select law; `retargetNoteMenu`; gutter selection +
   literal-100 audition. `notesOnKey` stays primary-track-only, matching `hitNote`.
3. `ApplicationSession.velocityPagePresenter()`; `EditorSurface` prompt loader;
   `VelocityPage.qml` loses the prompt; `VelocityPrompt.qml` focus-origin +
   palette-source change. Drawer-lane prompt tests address the card by objectName
   (`noteVelocityInput` etc.) and mount `EditorSurface`, so they stay valid.
4. `ShellWindow`: note-menu underlay + retarget/dismiss + invalidation close. The
   underlay owns press-forward and release-swallow; row Instantiators and
   `actionEnabled` bindings stay untouched.
5. RED→GREEN in `tst_ShellGridMenu` (menu + mounted round-trip), then
   `tst_SwiftRollSelection`, then the `tst_ShellNoteVisuals` painting trio.
6. Re-anchor `tst_EditorDrawer` focus/role messages; add the hidden-drawer predicate.
7. Run the lanes below; the ledger agent maps rows in the same commit (below).

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — latch draws (73/93/95/73), gutter
  selection/audition/history, drag-row byte/undo exactness, prompt regression.
- `deno task verify:shell --filter shell-grid-menu --verbose` — note-menu
  open/retarget/dismiss/invalidation + mounted prompt round-trip incl. hidden drawer.
- `deno task verify:shell --filter shell-note-visuals --verbose` — painting trio.
- `deno task verify:shell --filter shell-grid-input --verbose` and
  `deno task verify:shell --filter shell-menus --verbose` — regressions (PianoGrid
  press paths; menu topology verbatim).
- `deno task verify:qml --verbose` — re-anchored drawer prompt suite (transaction,
  buttons/focus, validation/dismissal, bounded keys, numeric input).
- `deno task verify:qml-roll --verbose` — mounted click-latch draw; roll regression.
- `deno task verify:bridge` — new accessor and tracked-property exposure.
- Runtime prerequisites: macOS desktop for the QML lanes; audio not required
  (auditions observed through the presenter callback, not the engine).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants; geometry stays base-font multiples; no palette literals in QML.
- One message-anchored predicate per fork clause; ledger-cited messages stay verbatim
  except the intentional re-anchors named in the contract.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify at freeze):
  - pencil_velocity: A001–A005 → click-latch anchors; A006–A015, A018–A020 →
    grid-menu retarget/dismiss anchors (A008/A009/A010/A016 pin native menu
    frame/window geometry → RETIRED-REPRESENTATION, sprint §4); A021–A025 → "a
    document edit retires the open note menu synchronously" + foreign-edit
    preservation; A026/A041/A045 seed guards → their scenarios' setup guards;
    A030–A033 → drag-latch + exact-snapshot anchors; A037 (primeMouseMove native
    priming) → RETIRED-REPRESENTATION; A039 → interlock regression + exact
    snapshots; A042 → double-click-delete scenario guard; A047 → the mounted
    "a right release over an unselected note selects it…" focus chain; A052 resize
    rows untouched (owned elsewhere).
  - velocity_prompt: A004/A005 → "…with the note's velocity selected" (literal 73);
    A013/A014/A019/A020 → latch-draw anchors; A016/A017/A023/A037/A038/A040/A049/
    A050/A052/A053/A056–A064/A083 → mounted round-trip/reopen/focus-return anchors,
    retiring as RETIRED-REPRESENTATION only where the clause pins the popup's native
    window identity rather than observable delivery; A018 → afterDraw-baseline
    anchor; A047/A070/A072/A103 → mounted + exact-snapshot pairs; A051/A054 →
    outside-dismissal preservation and the interruption-recovery fresh drag (extend
    `interlock.swift` if that owner fits — one anchor each); A001/A022/A042/A065/
    A074 and A021/A041/A055/A105 → the existing fixture guard + scenario
    undo-to-baseline restores.
  - pencil: A002/A009/A010/A014 → re-anchor existing `pencil.swift` guards (¶4);
    A016/A017/A018 → note-visuals painting trio; A020–A022 → gutter anchors.
- WCAG AA beats parity: the remounted card keeps audited GridPalette pairs; a failing
  prompt pair on the grid surface is fixed in the palette role, not the check.
- Accepted deviations (record in ledger reasons, do not code around): in-scene prompt
  vs fork popup window; card centered on the editor surface vs fork canvas window.

# Controller verification

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings`.
2. Native smoke (desktop): right-click an unselected note → menu opens and the note
   is selected; Set Velocity… shows the prompt over the roll with its velocity
   selected (also with the drawer hidden); OK writes one undo step and refocuses the
   roll; click a velocity-73 note then draw → the new note is 73; right-press another
   note while the menu is open → menu retargets; right-click empty space → dismisses;
   edit while the menu is open → it closes; click a piano key → all notes of that key
   select and audition.
3. Deletability: all three ledgers at zero GAP/PARTIAL (or RETIRED) → delete
   `proof.pencil_velocity.txt`, `proof.velocity_prompt.txt`, `proof.pencil.txt`;
   if the painting trio or gutter anchors defer, `proof.pencil.txt` stays open and
   the deferral is named per row.
