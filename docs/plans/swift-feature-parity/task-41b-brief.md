# Context

ED10 closure slice (task 41b): the pitch-bend ledgers the earlier slices left open —
`proof.vertex.txt` (36 GAP), `proof.raster.txt` (22 GAP), `proof.lifecycle.txt`
A036/A038–A093 (55 GAP + A039 PARTIAL; A037/A067 keep dispositions), `proof.fixture.txt`
(2 GAP). Classification visited every open row against its pinned C++ (`git show
`<Reference revision>:<Original>`). Result: **108 Behavior proof-only** (production
exists), **7 Behavior repaired** (four bounded repairs below; A046/A053/A087 focus
restore, A055 note retarget, A085 pass-through, A091/A092 host-loss close+commit),
**1 RETIRED-REPRESENTATION**, **0 Blocked**. Surface: the mounted `PitchBendPopup` over
`src/swift/app/pitchbend/*`; owners `PitchBendKernel/Scene/Presenter`,
`PitchBendPopup.qml`, the `EditorSurface.qml` overlay, `PianoGrid.swift` hit law.
Check files: `src/checks/rollcheck/pitch_bend.swift` (native, swiftcore-projectsession
via `SessionChecks.swift:74-76`), `src/checks/editorqml/tst_ShellPitchBend.qml`
(mounted, lane shell-pitch-bend, `ShellQmlTests.swift:64-65`). Fork-main `fceecd88`.

1. **Fork outside-press law** (`pitchbendeditor.cpp:560-590` @ fceecd88): the editor's
   window filter sees each press while open. Inside the form rect → normal delivery
   (blank chrome never dismisses). Outside the form: `focusNoteUnderCursor(scenePos)`
   runs first — the roll selects+foci the note under the cursor — and when it returns
   true the press is **eaten** (`return consume`) and the session cancels **with**
   roll-focus restore (`quickpopupsession.cpp:317-330` guards restore on window
   active); when it returns false (blank roll, headers, ruler) the session cancels
   **without** restore and, because `end()` reparents the layer out of the scene
   synchronously, the same press **falls through to the real UI** — a track-header
   click still selects that track (lifecycle A071–A085), a roll press-move-release
   on a note never becomes a drag (A044–A047, A051–A055). The underlay also swallows
   the paired release (`quickpopupsession.cpp:189-201`). Escape cancels with restore
   (A087); `WindowDeactivate`/`Hide` cancel without restore (`:258-266`), and a held
   graph gesture settles as a **commit** before that (grab-loss commits the unsettled
   preview, `pitchbendeditor.cpp:157-161`) — the A088–A093 net: closed, one new
   history entry, no focus restore. Delete/Backspace remove the focused graph's
   selected interior vertex only (`:605-616`).
2. **Current Swift** (`EditorSurface.qml:989-1045`): the overlay MouseArea eats every
   outside press with `cancelAndClose()` — no note retarget, no roll-focus restore,
   no pass-through (a header click dies on the overlay); `DocumentWorkspace.cancel(
   reason:)` (`:191-198`) never closes the popup, so `ShellWindow.qml:175-178`'s
   deactivate route (`cancelGridInput(3)` → `ApplicationSession.swift:546-556` →
   `workspace.cancel`) leaves it open; the graph MouseArea's `onCanceled` rolls a held
   gesture back (`PitchBendPopup.qml` graph `onCanceled: lane.cancelGesture()`).
   Four repairs (each RED-gated): (a) eaten-note press retargets selection and
   restores roll focus — new `PianoGrid.focusNoteUnderCursor(x:y:)`; the retarget's
   document-selection change already closes the editor through the proven task-40
   channel (`DocumentWorkspace.swift:250-268`); (b) non-note outside press passes
   through (`mouse.accepted = false` after close) so headers/ruler receive it;
   (c) Escape and the eaten press restore `swiftRollInput` focus; (d) host-window
   loss (reasons `windowDeactivated`/`hidden`) settles an in-flight lane gesture as
   a commit and closes without restore (`DocumentWorkspace.cancel`, new
   `PitchBendPresenter.settleAndClose()`; graph `onCanceled` settles the same way —
   "a lost grab is not an Escape-close").
3. **Vertex family — all proof-only.** Kernel: `hitTest` (`PitchBendKernel.swift:
   128-142`), press records `selectedTick` and starts a vertex drag (`:155-166`),
   drag moves interior points only with endpoints pinned (`:189-216`),
   `removeSelectedVertex` rejects endpoints (`:99-105`); scene routes press/drag/
   release with modifiers — Shift⇒line, Alt⇒fine (`PitchBendScene.swift:86-103`) —
   and commits deletes (`:94-98`); presenter routes Delete/Backspace
   (`PitchBendPresenter.swift:206-219`); the scene projects the selected ring
   (`PitchBendScene.swift:190-200`). Alt-drag = hit-test first, so Alt on a vertex
   drags it and Alt on empty canvas ramps fine (fork law).
4. **Raster family — all proof-only.** Fork render law: adjacent points exactly
   `fineTick` apart draw one angled segment, else horizontal+vertical
   (`pitchbendgraph_render.cpp:127-150`); a committed Shift line / Alt ramp is a
   fineTick-spaced point walk, so both render as true diagonals — the Swift scene
   ports the same law (`PitchBendScene.swift:164-174`), and the Shift-line byte
   contract is already proven (`pitchBendDocumentPredicates`,
   `pitch_bend.swift:264-477`). The form is an opaque `windowBackground` Rectangle
   (`PitchBendPopup.qml:37-45`, presenter `:61-65`). Pixel readback exists:
   `grabImage(...).pixel(x,y)` returns RGBA (`TextContrastAudit.js:161-162`).
5. **Fixture + deletability.** `proof.fixture.txt` A001 pins the anchor-selection
   invariant (one mounted predicate); A002 pins native `SongTab`/`QQuickView` setup
   → RETIRED-REPRESENTATION. After 41b every row of **vertex, raster, lifecycle,
   fixture** is MATCHED/RETIRED → **all four ledgers delete with this task's
   commit** (their C++ sources are already gone, `67544720`). `proof.curve.txt`
   (3 PARTIAL) and `proof.controller.txt` (8 PARTIAL) keep their recorded
   representation limits — untouched here, so the directory does not empty.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`* — one public invokable
  `focusNoteUnderCursor(x: Double, y: Double) -> Bool` reusing the roll's own
  note hit/selection law (task-35 path); arms no drag state.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — overlay outside-press law
  (eat-with-retarget vs pass-through), Escape/eat roll-focus restore.
- `src/swift/app/pitchbend/PitchBendPresenter.swift` — `settleAndClose()`.
- `src/swift/app/pitchbend/PitchBendScene.swift` — lane `settleGesture()` (release-
  path settle for a held gesture; no new state).
- `src/ui/songview/quick/PitchBendPopup.qml` — graph `onCanceled` settles instead
  of rolling back.
- `src/swift/app/DocumentWorkspace.swift` — `cancel(reason:)` closes the popup with
  settle-commit semantics for `windowDeactivated`/`hidden`.
- `src/checks/rollcheck/pitch_bend.swift` — native vertex, gesture-state and
  host-cancel blocks; existing predicate messages byte-identical.
- `src/checks/editorqml/tst_ShellPitchBend.qml` — mounted vertex, raster and
  dismissal-cause functions; existing fifteen tests byte-identical except the
  A039 probe correction below.
- Ledgers (controller-delegated ledger agent, this task's commit): row edits +
  deletion of `src/checks/pitchbend/proof.{vertex,raster,lifecycle,fixture}.txt`.

No C++, no `ApplicationSession.swift`/`ShellWindow.qml` (routing already exists), no
`PitchBendKernel.swift`, no harness/registration edits. Sizing exception: one
behavior family (the pitch-bend surface's ED10 remainder) over 9 files with one
verification-surface set — named for the dispatch table.

# Prerequisites

Task 41 landed; **dispatch after task 42 lands** (it owns `PianoGrid.swift`
mid-flight). `EditorSurface.qml` is otherwise unowned. Task-51a's
`tst_ShellGridInput.qml`/`ShellQmlTests.swift` work does not overlap this write set.
macOS host for the shell lane.

# Interface contract

- `PianoGrid.focusNoteUnderCursor(x: Double, y: Double) -> Bool` (roll-local
  coordinates): selects (and only selects) the note hit at the point under the
  roll's click/hover law; returns true iff one was selected. No drag arming, no
  edit cursor move, no revision change.
- Overlay press law (`EditorSurface.qml` pitchBendPopupLoader MouseArea
  `onPressed`): press inside the popup form rect → not accepted (unchanged; the
  popup's own shield keeps the editor open). Press outside: map to roll coords
  when over the roll plot and call `focusNoteUnderCursor`; if true →
  `mouse.accepted = true` (press+paired move/release eaten, no roll drag, revision
  unchanged) and after close `rollInput.forceActiveFocus(Qt.MouseFocusReason)`;
  if false or outside the roll → close then `mouse.accepted = false` so the same
  press delivers to the UI below (track-header row selects its track, ruler
  behaves). `onWheel` stays accepted.
- `Keys.onEscapePressed` (Loader) and the eaten-press path: after
  `cancelAndClose()`, `rollInput.forceActiveFocus(Qt.OtherFocusReason)`. The
  host-loss path restores nothing.
- `PitchBendPresenter.settleAndClose()`: settles each lane's in-flight gesture as
  if released at its last sample (commit when the gesture changed anything; one
  history entry), then closes exactly like `cancelAndClose()` minus gesture
  rollback. `PitchBendScene.settleGesture()` is the lane-level settle the popup's
  `onCanceled` and the presenter both call; completed-gesture/undo behavior is
  untouched (all closed curve/controller rows stay green).
- `DocumentWorkspace.cancel(reason:)`: for reasons `windowDeactivated` (3) and
  `hidden` (2) it now also calls `pitchBend.settleAndClose()`; all other reasons
  and the existing `deactivate()`/`teardown()` paths are unchanged.
- New anchors (message-anchored, task-20 style; one per fork clause group):
  - native `pitchBendVertexPredicates`: "an interior vertex hit selects its tick",
    "an Alt drag moves the selected interior vertex in one entry", "undoing the
    Alt drag restores the moved vertex", "deleting a selected interior vertex
    writes one entry and keeps both endpoints", "undoing the vertex delete
    restores the point", "endpoint vertices select but never delete",
    "a held graph gesture settles as a commit", "host-window loss settles and
    closes the editor without restoring roll focus".
  - mounted `tst_ShellPitchBend.qml`: "clicking an interior vertex selects it",
    "an Alt pointer drag moves the interior vertex", "Delete and Backspace remove
    the selected interior vertex", "endpoint deletion is rejected without an
    entry", "the popup surface is opaque window background", "a committed Shift
    line paints its diagonal", "the Alt ramp repaints after Escape and reopen",
    "clicking the anchored note dismisses the editor and keeps it selected",
    "an outside note press is eaten without dragging the note",
    "an outside blank press passes through to the roll",
    "a track-header click passes through and selects its track",
    "dismissal returns keyboard focus to the roll input",
    "the roll advertises the arrow cursor after dismissal",
    "the roll keeps its note-edge cursor across dismissal",
    "focus escaping to the roll keeps the editor open",
    "the re-anchor command replaces the open editor",
    "host-window loss commits the held stroke and closes without focus restore",
    "the mounted fixture holds exactly its anchor note selected".

# Implementation steps

1. RED: mounted predicates for the four repairs (probe points from `visibleNote`,
   the add-track row `TrackHeaderBand.qml:371`, font-derived margins only). Each
   must fail on the pre-repair tree.
2. Production repairs in the order above (PianoGrid invokable → overlay law →
   focus restore → settle/close routing).
3. Native vertex/gesture/host-cancel blocks (reuse `pitchBendCheckScene`,
   `pitchBendStroke`, `pitchBendLaneHasPoint`, `pitchBendSyntheticSession`,
   `coreTimeBytes`; read `selectedTick`/gesture state directly).
4. Mounted vertex functions: extend `strokePitchCanvas` with a modifiers argument;
   click/Alt-drag/Delete journeys on both graphs (data rows pitch+mod); endpoint
   rejection reads revision + serialized lane state.
5. Mounted raster function: `grabImage` of the surface, crop the popup rect
   (`pitchBendPopup` mapped to scene), assert per-pixel alpha 255 and the
   published `appearance.windowBackground` at three font-derived insets;
   `coloredHits` re-implementation — 7 interior samples along the stroke line,
   ≥ 4 non-background hits — for the Shift line and, after Escape+reopen, the Alt
   ramp; save both frames via the polyphony `grabToImage`/`artifactPath` pattern.
6. Mounted dismissal functions: escape/roll-click/stray-note (drawn through the
   real roll input, the `tst_ShellGridInput.qml:179-181` draw pattern with
   `grid.drawThreshold`), focus/cursor, inside/outside/header pass-through,
   re-anchor (`openViaG` on the open editor), host-loss (`shell.session.
   cancelGridInput(3)` with a held graph press+move).
7. Correct the A039 probe: `test_cancelReopenAndOutsideClickDoNotEdit`'s outside
   click moves from the blank host edge to the anchored note's center (message
   verbatim); re-run the whole lane.
8. GREEN on the lanes below; classify any other failure: harness artifact → fix
   predicate; behavior gap → stop, report, minimal repair inside the write set.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-pitch-bend --verbose` — all fifteen
  existing tests plus the vertex/raster/dismissal functions (macOS host).
- `deno task verify --filter swiftcore-projectsession --verbose` — native vertex,
  settle and host-cancel predicates beside the existing pitch-bend blocks.
- `deno task verify:qml-roll --verbose` — EditorSurface overlay regression.
- `deno task verify:bridge` — new `focusNoteUnderCursor`/`settleGesture`/
  `settleAndClose` surface.
- Controller-side after the ledger handoff: `deno task proof check`,
  `deno task proof check --executed`, `deno task proof check --strict-mappings`.

# Task-specific constraints

- No new C++; no comments — delete stale ones inside edited regions; no pixel
  constants (probe insets/offsets from `root.baseFontPx`/font metrics; hit radii
  from published geometry); no palette literals (compare against published
  `appearance.windowBackground`); no new lanes, registrations or debug seams.
- Existing anchor messages stay byte-identical; the four RED repairs are the only
  expected RED→GREEN pairs — everything else is proof-first.
- Registered deviations (record in ledger reasons, do not code around): the
  mounted form is a single-scene Loader overlay, so destroyed-editor rows map to
  Loader deactivation (findChild null) and the re-anchor replacement to a new
  popup item identity; the host-loss stimulus is the production seam
  `cancelGridInput(3)` (QML cannot synthesize `WindowDeactivate`) and the settle
  rides the close path rather than a separate grab-revoke step — net document and
  focus behavior match the fork; the note-edge cursor is the advertised
  `cursorKind` shape (`SizeHorCursor`), not the fork's native pixmap cursor;
  `hasGesture` reads the lane's published live-preview state.
- Implementers never edit ledgers. Ledger mapping (agent; rows compact on close):
  - vertex: A001–A003/A006–A008/A014–A016/A022–A024/A030–A032 → realize anchors;
    A004/A005/A009 → stroke/entry/interior anchors; A012–A013 → "clicking an
    interior vertex selects it"; A017–A021 → the Alt-drag anchors; A025–A029 →
    the delete anchors; A033–A036 → endpoint-presence/selection anchors; A037–
    A038 → "endpoint deletion is rejected without an entry". Delete the ledger.
  - raster: A001–A005, A010–A011, A014, A016–A021 → realize/grab facts;
    A006–A009 → "the popup surface is opaque window background"; A012–A013/A015 →
    "a committed Shift line paints its diagonal"; A022 → "the Alt ramp repaints
    after Escape and reopen". Delete the ledger.
  - lifecycle: A036/A038/A041–A043/A056/A058–A059/A068/A075–A076/A080–A082/A086/
    A088–A089 → realize facts; A039 PARTIAL→MATCHED (note-point probe); A040,
    A044–A045, A047, A051–A052, A054 → the eaten-press anchors; A046/A053 →
    "dismissal returns keyboard focus to the roll input"; A048–A050 → stray-note
    staging facts; A055 → the retarget clause of the eaten-press anchors;
    A057 → "the roll advertises the arrow cursor after dismissal"; A060–A062 →
    "focus escaping to the roll keeps the editor open"; A063–A066 → "the
    re-anchor command replaces the open editor"; A069–A070 → "the roll keeps its
    note-edge cursor across dismissal"; A071–A074 → add-track staging facts;
    A077 → inside-form retention; A078–A079 → "an outside blank press passes
    through to the roll"; A083–A085 → "a track-header click passes through and
    selects its track"; A087 → the focus-return anchor; A090–A093 → the
    host-loss anchors. Delete the ledger.
  - fixture: A001 → the fixture-selection anchor; A002 → RETIRED-REPRESENTATION
    "native SongTab/QQuickView fixture setup; the mounted harness stages through
    ShellQmlBootstrap/openSong". Delete the ledger.
  - `proof.curve.txt`/`proof.controller.txt` untouched.
- Anchor-message rule: existing cited messages verbatim; only the A039 probe
  location changes.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, `deno task proof check --strict-mappings`;
   `deno task proof sites --area pitchbend` shows only the curve/controller
   PARTIAL rows open; the four ledgers are deleted with this task's commit.
2. Visual: re-run `deno task verify:shell --filter shell-pitch-bend --verbose`;
   inspect the saved Shift/Alt ramp frames — the diagonal is painted along the
   stroke line; the popup face stays frozen against
   `src/checks/fixtures/visual/macos-dpr1-font12/quick/vanilla/pitch-bend-popup.{png,json}`.
3. Native smoke (desktop): launch the built app, open the pitch-bend popup —
   click a lane vertex (ring appears), Alt-drag it, Delete it, click an endpoint
   and Delete (nothing happens); press G on the open popup (re-anchors); click a
   note behind the popup (popup closes, that note selected, roll focused, no
   drag); click a track header behind the popup (popup closes, track selects);
   Escape (roll focused); mid-stroke app switch (popup closes, stroke committed,
   one undo restores it).
