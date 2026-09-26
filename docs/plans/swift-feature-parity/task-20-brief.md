# Context

ED10 first slice: the pitch curve's **stroke input → history → note-span
confinement → SMF serialization** contract, spec `src/checks/pitchbend/proof.curve.txt`
(123 sites: 119 GAP, 2 PARTIAL, 2 MATCHED). This slice covers rows A001–A057
(53 GAP + PARTIAL upgrades A011/A013; A008/A010 stay MATCHED untouched) — the
eight curve.cpp test functions `bendrFixtureUndoPreservation`,
`shiftDragDrawsLinearRamp`, `freehandStrokePushesSingleUndoCommand`,
`standardUndoShortcutRestoresCurve`, `navigationKeysDoNotModifyCurve`,
`stackedStrokesPushIndependentUndoCommands`, `freehandStrokeConfinedToNoteSpan`,
`pitchWheelSerializesValidSmfEvents`.

The surface already exists end to end: `EditorSurface.qml` mounts
`PitchBendPopup.qml` (objectNames `pitchBendGraph`/`modWheelGraph`/
`pitchBendReset`/`modWheelReset`/`bendRangeSpin`) on
`pitchBendPresenter.isOpen`; input flows `GraphCanvas.MouseArea →
PitchBendLane.press/drag/release → onCommit → PitchBendPresenter.commit →
SongDocument.writeLane` (src/swift/core/EventEditing.swift:383-406), which
commits one `DocumentMutation` per call — the single-undo-command contract.
`documentDidChange` keeps the popup alive across undo (PitchBendPresenter.swift:186-206).
So this is a proof task like task-18: write executing predicates against
existing production behavior; the 119 GAP rows say "feature not yet ported",
which is stale for this slice. The rest of ED10 (A058–A123) is explicitly
deferred below.

# Exact write set

- `src/checks/editorqml/tst_ShellPitchBend.qml` — four new test functions
  (suite uses descriptive names): Enter retention, keyboard-undo-while-open,
  navigation-key innocence, mounted stacked strokes. Existing three tests stay
  byte-identical (A011/A013/A-controller A023 PARTIAL reasons cite them).
- `src/checks/rollcheck/pitch_bend.swift` — extend
  `runPitchBendChecks(_ report:)` to `runPitchBendChecks(_ report:, session:)`
  with document-level predicates appended after the existing kernel section;
  existing kernel predicates unchanged.
- `src/checks/workspace/SessionChecks.swift` — line 68 call site passes
  `session` (the suite's staged `DocumentSession`, session_io.swift:10).

No production source edits. No new files, lanes or registrations:
`shell-pitch-bend` is registered at src/checks/editorqml/ShellQmlTests.swift:64-65
(fixtures `songs("mus_route101")`); the native predicates ride
`swiftcore-projectsession` (checkcatalog.cpp:124). Do NOT touch
`src/checks/editcheck/TimeCorpusChecks.swift` (already owns writeLane corpus
rows) or the other five pitchbend ledgers. Any predicate failure outside the
two flagged divergences below is a BEHAVIOR-GAP → stop and report; no
production patching.

# Prerequisites

None blocked. Task 18's shell-tabs/swiftcore lanes are settled. The presenter,
document history and shell mount all exist in-tree. The controller serializes
the shared build after sibling writers settle (BriefEventListEdits /
BriefAutomationPointMenus also touch editorqml/swiftcore files, none shared).

# Interface contract

- Native predicates construct the production object graph the way
  `DocumentWorkspace.swift:71-75` does: `PitchBendPresenter(session:grid:palette:)`
  over the suite's real `DocumentSession`, then `presenter.configure(fontPx:lineSpacing:dpr:)`
  (the same API `EditorSurface` calls on mount) so geometry is non-degenerate,
  select a real note on the session, `openSelected()`, and drive
  `presenter.pitchGraph().press/drag/release(x:y:modifiers:)` — the exact
  entry points QML calls (PitchBendScene.swift:86-106). `Qt.ShiftModifier =
  0x0200_0000`.
- Undo arithmetic via `session.document.history.undoIndex` (SongHistory.swift:234,
  documented QUndoStack::index mirror); SMF bytes via
  `try session.document.captureSave().bytes` (SongDocument.swift:389-404; see
  `coreTimeBytes` in src/checks/editcheck/TimeRangeChecks.swift:1195 for the
  pattern); lane points via `session.document.lanePoints(track:lane:)`
  (SongDocument.swift:338); bend event validity from the public
  `document.file` chunk events (status nibble 0xE, data bytes ≤ 0x7F).
- QML tests reuse the suite's helpers (`openSong`, `visibleNote`, `surface`,
  `waitForNative`) and objectNames; strokes via `mousePress/mouseMove/mouseRelease`
  on `pitchBendGraph` with `canvasRect` fractions (never pixel constants).
- Keyboard undo (A024) must fire the real window shortcut
  (KeybindingRegistry.swift:115, `.window` scope, standard `.undo`), e.g.
  `keyClick(Qt.Key_Z, Qt.MetaModifier)` on macOS / `Qt.ControlModifier`
  elsewhere — resolved from `Qt.platform.os`, NOT `app.requestUndo()`.
- Every new assertion carries a contract-shaped message (`report.expect(...,
  cppID:, message:)` / QML `verify(cond, "…")`) the ledger agent can cite
  verbatim; report exact strings + file:line when done.

# Implementation steps

1. Native document-level predicates in `pitch_bend.swift` (all through the
   production chain above): (N1) `writeLane` on CC 0x14 across a note span →
   `undoIndex + 1`, point visible in `lanePoints`, undo restores index (A001–A003);
   (N2) `captureSave().bytes` equal before/after undo, note span still present
   (A004–A005); (N3) Shift stroke → exactly `+1`, interior points (tick strictly
   inside span) ≥ 2, no adjacent equal values by tick, undo → bytes equal (A009,
   A011, A012, A013); (N4) freehand stroke → `+1` (A016–A017); (N5) stacked
   strokes → `+1` each, bytes differ from previous each time, two undos restore
   first then baseline bytes exactly (A035–A043); (N6) full-canvas stroke → all
   `.pitchBend` lane points within `[note.tick, noteEnd]`, ≥1 nonzero interior
   write, `noteEnd` point keeps its pre-stroke effective value (A046–A050);
   (N7) after a stroke the track's bend events in span exist with data bytes
   ≤ 0x7F (A053–A057); (N8) each navigation key through
   `routeUnclaimedKey` → returns false, `undoIndex` and bytes unchanged (A030–A031).
2. QML predicates in `tst_ShellPitchBend.qml`: (Q1) open journey asserts popup +
   graph realized (A006–A007, A014–A015, A021–A022, A033–A034, A044–A045, A051–A052
   ride each journey's own liveness verify); (Q2) after a committed freehand
   stroke the popup stays open, `keyClick(Qt.Key_Enter)` keeps it open and
   `findChild(view, "pitchBendPopup")` is the same instance (A018–A020);
   (Q3) real-mouse Shift stroke, then the bound undo key → revision text and
   `curveSegmentCount` restore, `canRedo` true, popup open,
   `pitchBendGraph.activeFocus` true (A023–A024, A027–A028); (Q4) loop the eight
   navigation key rows with the popup open (A029 liveness) → revision text
   unchanged and popup open after each (A030 mounted delivery, A032); (Q5) two
   mounted strokes → revision text changes
   twice, keyboard undo twice walks both back (A037, A039 mounted complement).
3. Run the lanes; on failure classify against the two flagged divergences below
   before escalating. Report predicate message strings + file:line for the
   ledger handoff; do not edit any proof file.

# Acceptance predicate

All new predicates pass through the production path; no production file
changed. `test_noteScopedCurveAndControls` and the other two existing tests
still pass unchanged. Controller-run named checks after the writer freezes:
- `deno task verify:shell --filter shell-pitch-bend --verbose`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:bridge`
- After the controller-owned ledger handoff: `deno task proof check`,
  `deno task proof check --executed`, `deno task proof check --strict-mappings`
  (the 55 addressed rows leave the strict list; deferred rows stay GAP).

Proof ownership: the implementer does NOT edit ledgers. The controller's
ledger-agent updates `proof.curve.txt` afterwards in the same commit. Intended
dispositions (message-anchored executing predicates per row): MATCHED —
A001–A007, A009, A011–A024, A027–A057 (53 rows; the steps above name each
row's predicate group); PARTIAL — A025, A026 (shortcut-triggered undo proven
via revision/curve/canRedo plus native index/byte arithmetic on the API undo
path; no single predicate executes shortcut and index together).
RETIRED-REPRESENTATION: none in A001–A057. Deferred rows
A058–A123 stay unchanged GAP.

# Visual parity

Counterpart at `b28f082758e63ef3cd2868f9205b96acfffb94f5`:
`src/ui/songview/quick/PitchBendPopup.qml` (popup chrome), C++ owners
`src/ui/pitchbendeditor.{cpp,hpp}`, `src/ui/pitchbendgraph.{cpp,hpp}`,
`src/ui/pitchbendgraph_render.cpp` (paint), `src/ui/pitchbendgeometry.h`
(`resolve(font,dpr)`), `src/ui/pitchprojection.{cpp,h}`. Recorded references:
`src/checks/fixtures/visual/{macos-dpr1-font12,macos-dpr1-font16,macos-dpr2-font12,macos-dpr2-font16}/quick/vanilla/pitch-bend-popup.{png,json}`
(in-tree; JSON pins environment + named regions, e.g. form 292×349 at font 12).

Contract to reproduce (already shipped in this tree): opaque
window-background form with hairline outline; title "Note automation" + note
subtitle; one controls row `BENDR` label+spin then `LFO speed` label+spin; two
equal stacked graph lanes (pitch bipolar with `0` axis label, mod unipolar);
per lane: title left, monospace live readout right of the header band, Reset
button right-aligned above the canvas, `Note on` left / dynamic end label
right beneath; focus ring only on the focused canvas. All chrome derives from
`PitchBendGeometry` font ratios (PitchBendGeometry.swift:36-58: canvas
20·font × 8·font, form width (26/7+20+4/7)·font ≈ 24.29·font — matches the
font-12 fixture 292/12 = 24.33; height 349/12 = 29.08); colors are GridPalette
pairs (windowBackground/primaryText/secondaryText/outline/focusOutline) meeting
WCAG AA. This task changes no QML: current `PitchBendPopup.qml` differs from
b28f0827 only by the `swiftroll`→`Porydaw.Ui` import and `TimelineQuickItem`
swap (2 lines, verified). Visual acceptance: controller captures the mounted
popup through the shell lane (or native window) and compares structure against
the fixture PNG/JSON regions; any deviation is listed and justified. New
assertions must use canvas fractions, never pixel constants.

# Task-specific constraints

- No ledger edits by the implementer; no production edits; no new UI, lanes,
  registrations, debug seams or published check-only properties.
- Never use `origin/feature/swift-drawer-reactive` `*_gap.swift` files as spec;
  the automation-side ones are leads only, re-verified against this tree's API.
- No sleeps/timing hacks (`waitForNative` only); no code comments in
  Swift/QML; message anchors contract-shaped ("one stroke pushes exactly one
  history entry", not "index == 1").
- Flagged divergences: (1) [verified] Shift-line strokes step interior points
  on the fine lattice and interpolate with integer rounding
  (PitchBendKernel.swift:189,191,252-257) — no surviving curve row pins the
  Shift stride, but if N3's no-adjacent-equal predicate fails on the original
  fixture slope, that is a real A012 gap: stop and escalate. (2) [scout-reported,
  unverified] kernel `snap()` is static modulo and does not re-anchor across
  time-signature boundaries — belongs to the deferred grid slice (A112), verify
  there.
- Deferred to follow-up briefs (stay GAP): A058–A073 anchoring/lifetime (pairs
  with proof.lifecycle `externalNoteMutationDismissesPopup`,
  `unterminatedNoteSpanRejectsEditing`); A074–A087 preview across external edit
  (pairs with proof.controller `controllerUndoChainingPreservesPopupSession`);
  A088–A096 + A115–A123 mod wheel and resets (pairs with proof.controller
  `resetButtonZeroesCurveAndRestoresEndValue`); A097–A114 Alt fine-grid and
  signature-boundary snapping (pairs with proof.vertex `vertexAltDragMovesPoint`).
  Sibling ledgers (vertex/controller/lifecycle/raster/fixture,
  selectionkey localinputtier_pitchbend) are out of scope and untouched.
