# Context

ED10-2: the pitch-bend popup's **G-key anchoring law, owner lifetime, and
external-edit preview contract** (task-20 deferrals). Surface: the mounted
`PitchBendPopup` (EditorSurface.qml:942-998) over `src/swift/app/pitchbend/*`.
Fork-main `fceecd88`. Like task-20 this is proof-first: the production path
exists end to end (`KeybindingRegistry.swift:156` `roll.pitch_bend` editorRouted
G → `ShellPresenter.routeEditorKey` :334-366 → `NoteCommands.swift:44-46` →
`PianoGrid.onPitchBendRequested` → `PitchBendPresenter.openSelected`
:91-134), so the deliverable is executing predicates; production edits only
after a real gap is reported (constraints).

1. **G-key anchoring law** (`git show fceecd88:src/checks/pitchbend/lifecycle.cpp:56-99`):
   with a selected note and roll focus, G opens the popup; the form is hosted in
   the same window as the roll, intersects the host rect, is horizontally
   centered on the selected note within `width/2 + 12`, and its top/bottom sit
   inside the host; shrinking the window (−160 px, ≈12·base font) keeps the
   *same* editor open and re-clamps the form inside the shrunken bounds; the
   note selection survives the whole journey. Swift mount already centers on
   `anchorX + anchorWidth/2`, clamps x to `[0, parent.width − width]`, places
   below/above the note, clamps y (`EditorSurface.qml:964-979`); the x/y
   bindings re-run on parent resize, and `isOpen` is resize-independent —
   the re-clamp law is expected to hold as mounted.
2. **Owner lifetime** (`curve.cpp:210-243`, `lifecycle.cpp:155-164, 370-383`):
   the popup is owned by its note span. `openSelected` spans exactly the
   selected note (`kernel.endTick == noteEnd`); an external mutation that
   breaks the span (delete, move; fork deletes/moves the anchored note) closes
   the popup and unloads its item — and it must **not** re-anchor to a
   same-tick/same-key impostor note (`curve.cpp` `duplicateNoteAtSameTick…`);
   undo restores the note and exact prior SMF while the popup stays closed. An
   **unterminated** note (note-on without note-off) rejects editing: G opens
   nothing and changes no bytes. Swift: `documentDidChange`
   (PitchBendPresenter.swift:194-212) closes on `spanStillPresent()` failure
   (:265-271 compares track/tick/endTick/pitch); `openSelected`'s guard
   (:96-98 `endTick` nil or `end <= tick`) refuses unterminated notes;
   `DocumentWorkspace.sessionDidChange` (DocumentWorkspace.swift:308-335)
   dispatches `.document` → `documentDidChange()` then `.selection` →
   `cancelAndClose()` — the dispatch order this task mirrors natively.
3. **External-edit preview** (`curve.cpp:249-284`): with a live gesture
   (press+move, no release) on the pitch graph, an external lane write over the
   note span (fork: CC 0x15, points `{{tick,23},{end,22}}`) pushes exactly one
   history command and must **not** resolve the live preview — the graph keeps
   its in-gesture points across the edit, its undo (bytes restored) and its
   redo; the gesture stays active; Escape still closes afterwards. Swift:
   `documentDidChange` early-returns while `kernel.hasGesture`
   (PitchBendPresenter.swift:197-199), so the preview is expected to survive;
   the popup stays live across undo via the mounted window binding (proved by
   task-20 S046–S049/S057–S060).

# Exact write set

- `src/checks/editorqml/tst_ShellPitchBend.qml` — three new test functions
  (G-key anchoring + window-shrink re-clamp; external note mutation via real
  window commands; live-gesture preview across undo/redo) plus any shared
  helper they need. Existing seven tests stay byte-identical.
- `src/checks/rollcheck/pitch_bend.swift` — new predicate blocks inside
  `runPitchBendChecks(_ report:, session:)` (impostor lifetime, external-edit
  preview, unterminated refusal), reusing `pitchBendCheckScene`,
  `pitchBendCanvasPoint`, `pitchBendLaneHasPoint`, `pitchBendSpanAlive`,
  `coreTimeBytes`. Existing predicates unchanged.
- Conditional (only after a reported gap, minimal fix): `PitchBendPresenter.swift`,
  the EditorSurface.qml:942-998 mount block. `PitchBendPopup.qml` chrome,
  `SessionChecks.swift` (signature unchanged), CMake, registrations: no edits.
  EditorSurface.qml is a controller-hot file (38/44/46/48 share it) — a repair
  takes the sequenced slot, not a parallel one.

# Prerequisites

Task 20 landed (`03df718c` — same two files' helpers, curve A001–A057). No
other interface deps. Task 41 (ED10-3) builds on this brief's rows and must
dispatch after it. Parallel-safe with 37/39/43 (no shared files). macOS host
for the shell lane.

# Interface contract

- Native blocks construct dedicated synthetic sessions exactly as
  `session_editor_semantics.swift:53-57` does (`SongDocument(file:
  makeMidiFixture(), config:…, source:…, trackBudget:…)` over
  `DocumentSession(document:service:lease:…)`), then mirror the production
  dispatch by wiring `session.onChange` to the two pitch-bend rules of
  `DocumentWorkspace.sessionDidChange` (DocumentWorkspace.swift:311-314,
  330-331, same order): `.document` → `presenter.documentDidChange()`,
  `.selection` → `presenter.cancelAndClose()`. The suite session passed into
  `runPitchBendChecks` is never re-wired or mutated by the new blocks.
- Impostor block: over a synthetic session, duplicate the scene's host note
  via `document.addNotes([NewNote(track: 0, tick: note.tick, pitch:
  note.pitch, duration: note.duration, velocity: …)])` (exact duplicates are
  legal, NoteEditing.swift:63), assert two assigned distinct ids at the same
  tick/pitch, open on the original, assert `pitchGraph().kernel.endTick ==
  noteEnd`, then `document.deleteNotes([original.id])` → `presenter.isOpen ==
  false`; impostor still resolvable, original gone; `history.undoDocument()`
  restores index, exact bytes (`coreTimeBytes`) and the note while `isOpen`
  stays false.
- External-edit block: open, `press` at canvas (0.25, 0.70) + `drag` to
  (0.75, 0.30) with no release → `kernel.hasGesture`; capture
  `kernel.points` (+ `endValue`) as the preview; `document.writeLane(track:
  0, lane: .controller(0x15), from: note.tick, through: noteEnd, points:
  [LaneWrite(tick: note.tick, value: 23), LaneWrite(tick: noteEnd, value:
  22)])` → `undoIndex == before + 1`, bytes differ, dispatch → points/endValue
  unchanged and gesture still active; `undoDocument()` → index/bytes restored,
  dispatch → preview + gesture intact; `redoDocument()` → index +1, bytes
  differ, dispatch → preview intact; `cancelAndClose()` → `isOpen == false`.
- Unterminated block: synthetic document = `makeMidiFixture()` with one
  unpaired note-on appended to the note chunk; select that note; `openSelected()`
  returns false, `isOpen` false, `coreTimeBytes` unchanged.
- Mounted functions (helpers `openSong`/`surface`/`visibleNote`/`waitForNative`):
  - *G-key anchoring*: click a visible note (selects), `roll.forceActiveFocus(
    Qt.OtherFocusReason)` + `tryCompare(roll, "activeFocus", true)` (the
    tst_ShellGridInput.qml:442-443 pattern), `keyClick(Qt.Key_G)` → `isOpen`
    and `findChild(view, "pitchBendPopup")` realized. Then map the popup into
    `shell.contentItem` and assert intersects/inside host bounds (x ≥ 0, y ≥ 0,
    right/bottom ≤ content size). Then shrink `shell.height` by
    `12 * <resolved base font px>` (fraction/multiple only, never a raw px
    constant) → `tryCompare(shell, "height", …)`, same popup object identity,
    `isOpen` still true, bounds re-clamped inside the shrunken host, and
    `JSON.parse(grid.noteSummary).some(n => n.selected)` still true.
  - *External mutation*: click note → `keyClick(Qt.Key_Delete)` (roll focused)
    → undo key (`Qt.MetaModifier`/`Qt.ControlModifier` + Z by `Qt.platform.os`,
    the task-20 rule) restores the note → re-click the note → G opens → redo
    key (⇧+Z) re-deletes externally → `isOpen` false and
    `findChild(view, "pitchBendPopup") === null`.
  - *Live preview*: stroke once and close (Escape), reopen via G, `mousePress`
    + `mouseMove` on `pitchBendGraph` (no release), record
    `curveSegmentCount`, fire the undo key → popup open, segment count and
    revision-derived lane state unchanged, then redo key → still open and
    unchanged; `mouseRelease`, `keyClick(Qt.Key_Escape)` closes.
- Every assertion carries a contract-shaped message (task-20 anchor style);
  the exact strings are reported for the ledger handoff. No sleeps
  (`waitForNative`/`tryCompare` only); canvas/window fractions only.

# Implementation steps

1. Native: impostor lifetime block (facts → open → span identity → delete →
   close → undo restores) with the mirrored `session.onChange` dispatch.
2. Native: external-edit preview block (gesture → writeLane 0x15 → undo →
   redo → close), fork values mirrored.
3. Native: unterminated refusal block (unpaired note-on fixture).
4. Mounted: G-key anchoring + shrink re-clamp function.
5. Mounted: redo-redelete dismissal function; live-preview-across-undo
   function.
6. Run the lanes; on any failure classify: harness artifact → fix predicate;
   behavior gap → stop, report evidence, apply the minimal production fix in
   the conditional files only after reporting. Record RED→GREEN for the
   mounted journeys (G and redo paths are unproven today).

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-pitch-bend --verbose` — G-key
  anchoring, shrink re-clamp, external-mutation dismissal/unload, preview
  preservation, plus all seven existing tests unchanged.
- `deno task verify --filter swiftcore --verbose` — native impostor,
  external-edit preview, unterminated refusal on the production object graph.
- `deno task verify:qml-roll --verbose` — EditorSurface-mount regression (the
  popup loader block is shared with this lane).
- `deno task verify:bridge`
- Controller-side after the ledger handoff: `deno task proof check`,
  `deno task proof check --executed`, `deno task proof check
  --strict-mappings`.

# Visual parity

No chrome change: the popup face is frozen against
`src/checks/fixtures/visual/macos-dpr1-font12/quick/vanilla/pitch-bend-popup.{png,json}`
(task-20 contract). This task moves no geometry; if a repair touches the mount
block, the controller re-captures and compares the form regions before
accepting.

# Task-specific constraints

- No production edits unless a predicate fails; a failing predicate is
  classified and reported before any repair; structural discoveries stop the
  task. No new C++, no code comments (delete stale ones in edited regions), no
  pixel constants, no new published check-only properties, no new
  lanes/registrations/debug seams.
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent in this task's commit. Intended dispositions (message-anchored
  executing predicates; compact form on close):
  - `proof.curve.txt` (agent also rewrites the stale scope sentence
    "A058-A123 stay GAP" to A088-A123): A058–A064 → impostor-setup facts
    ("the duplicate note occupies the anchor note's exact tick and key with an
    independent identity"); A065 → existing "the Edit→Pitch Bend route opens
    the selected note's editor"; A066 → "the open editor's graph spans exactly
    the selected note"; A067 → "deleting the anchored note closes the editor";
    A068 → mounted "closing the editor unloads the popup item"; A069–A070 →
    "the same-tick impostor survives while the anchored span is gone";
    A071–A073 → "undo restores the anchored note and the exact prior song
    bytes"; A074–A075 → existing realize anchors; A076 → "an unfinished
    stroke keeps its live gesture"; A077 → "an external lane edit pushes
    exactly one history entry under the open gesture"; A078/A085 → "the
    external lane edit changes the serialized song"; A079/A083/A086 → "the
    live preview survives the external edit" (edit/undo/redo variants);
    A080–A081 → "undoing the external edit restores the exact prior song
    bytes"; A082 → "the gesture survives undo of the external edit"; A084 →
    "redo reapplies the external edit as one entry"; A087 → "Escape closes the
    editor after the external-edit cycle".
  - `proof.lifecycle.txt`: A001 → "the G key opens the selected note's editor
    from the roll"; A003 → existing realize anchor; **A004 →
    RETIRED-REPRESENTATION** (the fork's QuickPopupSession/shared-canvas
    pointer identity; the Swift popup is a single-scene overlay mounted in the
    timeline window at EditorSurface.qml:942-998 — the in-window placement is
    executed by the A005/A013 bounds predicates); A005 → "the anchored popup
    stays inside the window"; A009–A012 → "shrinking the window keeps the same
    editor open and realized"; A013–A015 → "the shrunken window re-clamps the
    anchored popup inside its bounds" (fork's trailing `assertNoteSelection`
    rides this group's message); A033–A034 → "an external note mutation closes
    the editor" (native moveNotes-byTicks + mounted redo journey); A035 →
    mounted unload anchor; A094–A096 → "an unterminated note exposes a
    degenerate editing span" (Swift `Note.endTick` is nil where the fork
    falls back to tick — note the deviation in the mapping line); A097–A098 →
    "the G route refuses an unterminated note without opening the editor";
    A099 → "refusing the unterminated note leaves the song bytes unchanged".
    Already-MATCHED A002/A006–A008/A037/A067 keep their dispositions.
  - Disclosed deviations (record, do not code around): destroyed-editor rows
    map to Loader deactivation (`findChild` null) instead of QPointer
    nullness; the mounted external mutation is a redo of a real Delete rather
    than the fork's programmatic moveNotes-to-track-1 (Swift's public mutator
    set has no per-note track move; the native block breaks the span with
    `moveNotes(byTicks: 1)` + `deleteNotes`, which `spanStillPresent` treats
    identically); native dispatch mirrors the two workspace rules instead of
    constructing a DocumentWorkspace.
- Blocked/untouched rows: `proof.curve.txt` A088–A123 (task-41: mod wheel,
  resets, snapping); `proof.lifecycle.txt` A016–A032 (description/idle/enter/
  internal-refresh — task-41 wheel+refresh), A036, A038–A093 (roll-click,
  inside/outside click, cursor, focus-return, deactivate dismissal causes —
  later pitch-bend/ED12 slices); sibling ledgers `proof.controller.txt`
  (task-41), `proof.raster.txt`, `proof.vertex.txt`, `proof.fixture.txt`,
  `selectionkey/proof.localinputtier_pitchbend.txt` untouched.

# Controller verification

After the writer settles and no check processes remain:

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — the two ledgers show executing
   anchors for every row flipped above and none for the untouched ranges.
2. Visual: re-run `deno task verify:shell --filter shell-pitch-bend
   --verbose`; the popup face is unchanged against the frozen fixture; if any
   mount repair landed, re-capture and compare the pitch-bend-popup form
   regions first.
3. Native smoke (desktop): launch the built app, open a song, click a note,
   press G — the popup opens centered on the note and fully inside the window;
   shrink the window — the popup re-clamps and stays open with the note still
   selected; press G on an unterminated (imported note-on-only) song — nothing
   opens; with the popup open and a stroke half-drawn, ⌘Z/⇧⌘Z leave the drawn
   preview untouched; Escape closes.
