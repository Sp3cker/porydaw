# Task 58 brief — roll key/gesture editing semantics + keyboard handover boundaries

# Context

Task 58 closes the selectionkey core families (~133 open rows), the
non-ruler keyboard boundaries task 53 handed over (`proof.keyboard.txt`
A047–A049, A061–A067, A071–A088; A040–A046 already closed), and the three
remaining `windowtier_keyboard` GAPs (A002, A035, A039). It is a proof task:
every production path below already executes — the implementer mounts real
key/pointer journeys and hardens swiftcore anchors, with production edits
only if a RED predicate exposes a divergence.

1. **Census (verified this freeze)**:
   - `selectionkey/proof.coreediting.txt` — 46 GAP + 2 PARTIAL (A041, A047).
   - `proof.corearrows.txt` — 12 GAP + 3 PARTIAL (A013, A014, A018).
   - `proof.gesturecommands.txt` — 16 GAP; `proof.gesturevelocity.txt` — 20 GAP.
   - `proof.gesturethumbs.txt` — 13 GAP; `proof.windowtier_gestures.txt` — 14 GAP.
   - `proof.localinput.txt` — 7 GAP (all fixture/shell-lifecycle representation).
   - `rollcheck/proof.keyboard.txt` handover — 28 GAP (A047–A049 repaint,
     A061–A067 duplicate, A071–A088 insert); task-53 brief §handover
     explicitly excludes these plus all non-ruler functions.
   - `proof.windowtier_keyboard.txt` — 3 GAP (A002, A035, A039); its 53
     PARTIALs stay open (not in scope).
2. **Fork law clusters** (`git show fceecd88:<path>`; scout-verified against
   ledger-quoted expressions):
   - `coreediting.cpp:63-93` — drawer transpose audition: Up key-down starts
     one live audition (velocity > 0), autorepeat key-up must not end it,
     physical key-up ends it (one velocity-0 emission).
   - `coreediting.cpp:101-132` — right-drag stages an active Lanes time
     selection; Delete removes only points inside it.
   - `coreediting.cpp:159-209` — pencil-hover Delete precedence matrix
     (note beats hovered point; time selection beats point; eligible hover
     deletes the point; hover miss changes no bytes).
   - `coreediting.cpp:218-250` — lane-scoped arrows: Up leaves the document
     untouched; Right moves the lane point to the snapped destination and
     translates the interval by the same delta.
   - `coreediting.cpp:275-354` — clipboard parity (paste lands at the
     committed cursor) and Select-All journeys (empty selection; after a
     ruler click it replaces the time selection).
   - `corearrows.cpp:124-251,267-313` — focus-routed arrows move only the
     selected notes (Up/Down ±1 key, Left/Right one grid snap; unselected
     notes unchanged; selection vector identical) with undo/redo round-trip.
   - `gesturecommands.cpp` — roll note-drag and automation pan own the
     surface: shared Delete is a consumed no-op mid-gesture, first Escape
     cancels only the gesture (selection restored/preserved), next idle
     Escape clears the time selection.
   - `gesturevelocity.cpp` — overlap node hit priority (idle/hover/selected/
     zoomed) and selected stem-drag retaining its selection while consuming
     edit keys until Escape restores it.
   - `gesturethumbs.cpp` — roll scrollbar thumb grab blocks Delete, Escape
     releases the grab, held-button movement stays inert, re-press drag
     works before Delete deletes again.
   - `windowtier_gestures.cpp:103-118` — drawer resize drag owns the surface
     (Delete consumed no-op; first Escape cancels keeping selection; next
     idle Escape clears it).
   - `keyboard.cpp:489-730` — Ctrl+D duplicates the time range once (undo
     +1, selection advances one span, cursor to the new end, range made
     visible; repeat duplicates the newest copy); Insert Time shifts only
     the scoped track/lane, keeps scope, resets cursor to range start, adds
     one undo step; invalid unused-track scope refuses with no prompt and
     no state change.
   - `windowtier_keyboard.cpp:258` (A039) — label-focus Up with an empty
     note selection is a no-op (fork stages its selection later, at :326).
3. **Swift current state — all paths execute**:
   - `NoteCommands.swift` (note scope: delete/transpose/nudge/resize/
     duplicate/selectAll) and `AutomationSelectionCommands.swift` (range
     scope: copy/cut/delete/duplicate/insertTime/removeContents/nudge/
     transpose, lane-Up refusal at :22-24, cursor+reveal at :108-134).
   - `ApplicationSession.swift:1370-1420` (`route`/`perform`: gesture guard
     via `survivesPointerGesture`, time-selection ownership, hover-delete,
     label-focus routing). `PianoGrid.swift:466` gesture guard;
     `withKeyboardSeed` already restores post-seed bytes (inner defer) and
     pre-seed state (outer defer) — the unwind anchors for the handover
     slot-restoration rows.
   - Mounted journeys already landing nearby behavior: `tst_ShellWindow.qml`
     `test_g` (arrows), `test_j` (Insert/Delete Time), `test_m` S086
     (label-focus Up transposes the selected note), `test_n` (label-focus
     Delete/SelectAll/Copy/Paste over a lane range); `tst_ShellGridInput.qml`
     `test_escapeCancel`/`test_ungrabCancel`/`test_hideCancel`/
     `test_windowCancelReasons`, draw/move/resize/undo journeys.
4. **Overlap rulings**: velocity-plot mount ownership stays with task-59
   (59a landed; plot surface is theirs) — this task owns the key-routing
   half and retires the pixel rows. Scrollbar thumb behavior consumes
   task-52's landed journey (52 landed; no new thumb surface here). Drawer
   resize production exists (`beginResize`/`cancelResize`); the grip journey
   mounts through the shellwindow lane, no drawer edits.

# Exact write set

- `src/checks/editorqml/tst_ShellGridInput.qml` — gesture-guard journeys:
  Delete mid-draw/mid-move consumed no-op, Escape cancel restores the
  staged selection, re-press drag works, thumb-grab Delete block + Escape
  release on task-52's mounted thumb.
- `src/checks/editorqml/tst_ShellWindow.qml` — extend the `test_j`/`test_n`/
  `test_m` area: Ctrl+D duplicate journey (lane range; note-flavor only if
  stageable), rejected-insert disabled journey on an empty-track range,
  lane-Up no-op + lane-Right nudge journeys, A039 empty-selection label-Up
  no-op journey.
- `src/checks/rollcheck/keyboard.swift` — harden the S057/S059 document-half
  anchors with the missing conjuncts (history-identity increment, retained
  scope fields, `session.editCursor` reset, camera-visibility via the
  existing `ensureRangeVisible` path); convert fixture guards that pin real
  behavior (A071–A073, A084–A085) from `report.fail` to `report.expect`.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only; deletions listed at the end.

No production Swift, no QML, no CMake, none of the hot files touched
(`ShellWindow.qml`, `ShellPresenter.swift`, `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `EditorSurface.qml`, `PianoGrid.swift`;
`tst_EditorDrawer.qml` untouched — in-flight task-56 owns its append).

# Prerequisites

Task-52 landed (consume its mounted thumb journey). Task-53 boundary frozen
(ruler rows and ruler drag excluded per its handover note). Task-59a landed
(plot surface is theirs). `tst_ShellWindow.qml` additions serialize with
task-65 (queue): 58 lands its journeys first or checkpoints between.

# Interface contract

- Message-anchored predicates (the `message:` strings are the ledger
  anchors and stay verbatim once written):
  - Roll gestures: "Delete during an active note gesture changes no notes";
    "Escape cancels the gesture and restores the staged selection";
    "a re-pressed drag works before Delete deletes again";
    "the thumb grab blocks Delete and Escape releases it".
  - Core editing: "Delete removes only the lane points inside the staged
    range"; "a hovered point survives a selected-note Delete";
    "a hover miss changes no document bytes";
    "lane-focus Up leaves the document untouched";
    "lane-focus Right moves the point and translates the interval";
    "Select All from empty selection takes the track notes and no time
    range"; "paste lands at the committed cursor".
  - Arrows/history: "only selected notes move by one key or one snap";
    "unselected notes stay byte-identical"; "the selection vector is
    identical after the arrow"; "one undo restores the pre-arrow state".
  - Handover: "Ctrl+D duplicates the range once and advances the selection
    and cursor"; "the duplicated range is camera-visible";
    "repeating Ctrl+D duplicates the newest copy";
    "track/lane Insert Time shifts only the scoped content, keeps scope,
    resets the cursor, adds one undo step";
    "the invalid scope refuses Insert Time with no prompt and no state
    change"; "the scenario unwind restores the slot's post-seed bytes".
  - Window tier: "label-focus Up with an empty selection edits nothing".
- Preservation contract: `NoteCommands`, `AutomationSelectionCommands`,
  `ApplicationSession.route/perform`, `PianoGrid` behavior unchanged
  (contingent edits only if a RED predicate exposes a real divergence —
  record RED→GREEN for that fix only); every existing S-message in touched
  files stays verbatim.

# Implementation steps

1. Handover swiftcore first: harden S057/S059 conjuncts; guard-to-expect
   conversions; map the five slot-restoration rows to the existing
   post-seed unwind anchor (no new code — the defer already does it).
2. Roll gesture guards in `tst_ShellGridInput.qml` (RED first: Delete
   mid-gesture and Escape-restore selection are unasserted today).
3. Lane Delete/precedence/arrow journeys in the shellwindow lane (RED
   first: lane-Up no-op and lane-Right nudge have no mounted predicates).
4. Ctrl+D duplicate + rejected-insert journeys (RED first); lane-flavored
   duplicate is the primary stimulus — note-flavored only if a Tracks note
   range proves stageable, else PARTIAL with the substitution named (bank
   A087/A088 precedent).
5. A039 journey (clear note selection, focus the Volume label, Up, assert
   no revision/selection change) plus A035's undo-index conjunct on the
   Return-activation journey and A002's focus clause retirement evidence.
6. Thumb-grab journey on task-52's mounted thumb; drawer-grip resize
   journey (press grip, Delete no-op mid-drag, Escape cancels keeping
   selection).
7. Run the lanes; report GREEN with predicate messages + file:line for the
  controller's ledger handoff.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-grid-input --verbose` — gesture
  guards + regressions.
- `deno task verify:shell --filter shellwindow --verbose` — duplicate,
  reject, lane-arrow, A039 journeys + `test_g`/`test_j`/`test_m`/`test_n`
  regressions.
- `deno task verify --filter swiftcore --verbose` — hardened S057/S059
  blocks + keyboard regressions (evidence `build/proof-evidence/
  swiftcore-projectsession.json`, `shell-grid-input.json`,
  `shellwindow.json`).
- `deno task verify:bridge`, `deno task format --check`.
- RED evidence for each previously unproved behavior before it passes.

# Task-specific constraints

- No new C++; no code comments; one message-anchored predicate per fork
  clause; real key/pointer delivery only (`keyClick`, `keySequence`,
  mouse press/move/release) — no second dispatcher, no synthetic
  forwarding, no focus memory (keyboard priority ruling).
- WCAG AA beats parity; base-font sizing only; no pixel constants beyond
  the fork's own stimulus numbers mirrored check-side.
- Implementers never edit ledgers; the controller's ledger agent flips in
  the same commit:
  - coreediting: B-rows → the new mounted anchors (A004/A006/A008 audition
    termini need an audition-emission observable — if none exists on the
    mounted surface, name the deferral and keep PARTIAL, never force);
    R-rows (A002/A003/A005/A007/A009–A012/A014/A016–A021/A026–A028/A030–A032/
    A035–A040/A042–A046/A048–A052) → `RETIRED-REPRESENTATION` (native
    fixture/window/focus/delivery; verify at Reference revision
    c17d966f). A041/A047 → MATCHED only if the exact-identity conjuncts
    execute, else PARTIAL with the residue named.
  - corearrows: A013/A014/A018 → MATCHED only with multi-note + unselected
    invariance + real undo/redo executed; R-rows (A003–A006/A010–A012/A016/
    A017/A019/A020, fixture/click-point/focus/delivery) →
    RETIRED-REPRESENTATION at acc55548; A007 (pure selection invariant) →
    MATCHED to the new incidental-click anchor.
  - gesturecommands/gesturevelocity/gesturethumbs/windowtier_gestures:
    behavior halves → new mounted anchors; native-grab/focus/pixel halves
    (all A001-class binding queries without Swift counterparts, paint/
    priority pixels, thumb-grab internals, grip-focus internals) →
    RETIRED-REPRESENTATION per sprint-3 §4 (representation sweeps retire
    inside the owning surface task).
  - localinput (7 GAP): all → RETIRED-REPRESENTATION (native shell/fixture
    lifecycle; ledger file stays — shared fixture across tiers).
  - keyboard handover: A048 (framebuffer equality) → RETIRED-
    REPRESENTATION; A047 (seed guard) → representation; A049/A067/A076/
    A081/A088 → MATCHED to the post-seed unwind anchor; A064–A066/A075/
    A077–A080/A084–A087 → new mounted/swiftcore anchors (alternate-stimulus
    substitution named where lane-flavored); A061–A063/A071–A074/A086 →
    MATCHED to the converted expect-guards once they execute.
  - windowtier_keyboard: A002 → RETIRED-REPRESENTATION (native
    `focusAutomationBand`; the mounted journeys stage QML focus instead);
    A035 → MATCHED only with an executed undo-index conjunct (else PARTIAL
    residue stays); A039 → the new empty-selection no-op anchor.
- After every row of a file is MATCHED/RETIRED, delete `proof.coreediting.
  txt`, `proof.corearrows.txt`, `proof.gesturecommands.txt`,
  `proof.gesturevelocity.txt`, `proof.gesturethumbs.txt`,
  `proof.windowtier_gestures.txt` in this task's final commit.
  `proof.localinput.txt`, `proof.windowtier_keyboard.txt` (53 PARTIALs),
  and `proof.keyboard.txt` (53 ruler/resize rows) stay.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof
   check --executed` (pre-deletion state shows the six ledgers closed with
   executing anchors), `deno task proof check --strict-mappings`, then
   `deno task proof sites --area selectionkey` / `--area rollcheck`
   confirms the six deletions and the surviving open rows.
2. Store-level smoke (headless, same lanes): no lane regresses against the
   pre-task run; `test_k`/`test_j`/`test_n` still green.
3. Confirm no hot-file diffs: `git status --porcelain` shows only the three
   check files plus ledger deletions.
