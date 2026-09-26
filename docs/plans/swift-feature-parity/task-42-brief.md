# Context

Task-42 (ED05-2): **scale-aware editing — prove the landed behavior, repair the one
ink divergence, close four ledgers.** Surface: the mounted roll + transport scale
controls (root/type/Highlight/Fold). Ledger areas: `src/checks/rollcheck/proof.scale_editing.txt`
(31 GAP + 4 PARTIAL), `proof.scale_projection.txt` (15 + 9), `proof.scale_fold.txt`
(11 + 2), `src/checks/workspace/proof.tabs_scale.txt` (38 GAP; preamble stale).
Fork-main = `fceecd88`. Builds on landed 38a (`92b0754b`: session-owned selection —
fold predicates reuse `DocumentSession.selectedNoteOrder`/`selectPrimaryTrack`).
1. **Laws already implemented — prove, do not rebuild.** The fork oracle
   (`src/checks/rollcheck/scale_editing.cpp`, production `src/ui/songview/`)
   maps 1:1 onto landed Swift:
   - Fold ±1 keys transpose by scale degree; any other magnitude (Shift =
     octave) is chromatic (`pianoroll_commands.cpp:215-221` ↔
     `NoteCommands.swift:151-166`).
   - Multi-note mapping resolves the batch in pitch order, distinct degrees
     for distinct sources, shared destination for repeated sources, off-scale
     source steps to the next member, boundary failure rejects atomically
     (`rangeedit.cpp:548-570` + `porydaw_scale::resolveDiatonicDestinations` ↔
     `ScaleProjection.swift:38-50` + `MusicalScale.swift:84-147`; committed via
     the mergeable absolute-pitch nudge `NoteMovement.swift:40-43`).
   - Fold draw is refused on off-scale rows (`PianoGrid.swift:643`, `:862`;
     `GridGesture.swift:104,127`); the exception row's piano-key press still
     auditions its true pitch (`PianoGrid.swift:899-913` — ungated).
   - Fold drags mutate the document only at release (`PianoGrid.swift:1005-1046`),
     so the projection cannot rebuild mid-drag; fold refresh preserves the
     centered pitch (`DocumentSession.swift:408-424`).
   - Keyboard chain mounted: Up/Down/Shift±Up → `roll.transpose_*`
     (`KeybindingRegistry.swift:157-160`) → `routeEditorKey`
     (`ShellPresenter.swift:334-366`) → `performGridCommand`. Existing swiftcore
     predicates already execute the pitch laws (`scale_editing.swift` S001–S008,
     `static/geometry.swift` S001–S017); every scale_editing PARTIAL names the
     same missing conjunct: *QML keyboard-event delivery untested*.
2. **Real divergence — fork highlight tint.** Fork `scale_projection.cpp:261-296`
   (A017–A030): Highlight paints ONE uniform tint `#b595fc` at exactly 20%
   (`(source*51 + background*204 + 127)/255`) on scale rows only — never on
   non-scale rows, the keyboard column, or a note face; no root emphasis;
   root/type changes move the lanes; Highlight composes with Fold on a visible
   occupied row. Swift paints two opaque tones (`GridScene.swift:397-401`,
   `GridPalette.swift:253-254` = `"#B4A7B7"`/`"#CEC1D2"`) from port `feda40bb`,
   backed by no parity or contrast ruling (non-text tint; WCAG AA inapplicable;
   the fork composite passes on every theme by construction). Repair to the
   fork law.
3. **tabs_scale** (`workspace/tabs_scale.cpp:49-156`): per-tab runtime state —
   defaults C/major/Highlight-off/Fold-off on every fresh tab; independence
   across tab switches; controls reflect the selected tab; track selection and
   delete-track/undo preserve the tab's scale state; state is never persisted
   (fork `scalecontroller.h:14-16`). Mounted follow-the-tab proof exists
   (`tst_ShellTransport.qml:424-461`, S186); the ledger preamble still claims no
   selector exists and its 6/38 tally contradicts its own rows (≥7 MATCHED).
4. **Undo/bytes invariants.** Every fork pass ends with two clauses —
   `gesture pass pushed an unexpected number of undo commands` and
   `QCOMPARE(doc.smf().write(), before)` — including view-only passes
   (`setScale*`/track switches push no history). No Swift predicate pins these.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`* — published `scaleFold`, `visibleRowCount`,
  `setScaleFold(_:)` (Interface contract). No behavior edits. *Hot file.*
- `src/swift/app/timeline/GridPalette.swift` — `scaleHighlight = "#33B595FC"`;
  delete `accidentalScaleHighlight` (sole consumer GridScene.swift:401).
- `src/swift/app/roll/GridScene.swift` — `rebuildStatic` highlight branch uses the
  single tint for every scale-member row (`:397-401`); black-key base lanes for
  non-members unchanged.
- `src/checks/rollcheck/scale_editing.swift` — fold boundary, gesture undo/bytes,
  view-toggle no-history, exception audition, fold draw gate, fold layout
  lifecycle, fold-on-then-edit, highlight-off track-switch predicates.
- `src/checks/rollcheck/static/geometry.swift` — production-fold-bound projection
  rows; highlight-pass no-history/bytes messages.
- `src/checks/workspace/session_editor_semantics.swift` — per-tab scale
  independence + track delete/undo retention block (two `DocumentSession`s).
- `src/checks/editorqml/tst_ShellTransport.qml` — extend
  `test_scaleControlsFollowSelectedTab`: initial Highlight/Fold-off defaults,
  toggle cycles, final first-tab assert.
- `src/checks/editorqml/tst_ShellGridInput.qml` — mounted fold key delivery
  (fold degree, fold octave, chromatic control, off-scale exception).
- `src/checks/rollqml/tst_SwiftRollSelection.qml` — mounted fold drag law
  (row gain, grab, mid-drag stability, degree commit, row collapse).
- `src/checks/rollqml/tst_SwiftRollPlots.qml` — mounted Highlight tint pixel
  probes (Windowing `pixelNear` pattern, `tst_SwiftRollWindowing.qml:176-188`).
- Ledgers (controller-delegated ledger agent, this task's commit): the four
  ledgers above.

`EditorSurface.qml` is **not** edited — the mounted tests reach the grid through
`session.songTabs.selectedPage.grid` / `findChild(surface, "swiftRollInput")`.
Hot-file note: Task48 owns the track-header menu Loader region and Task38b the
ruler-menu region of `EditorSurface.qml` and co-own `PianoGrid.swift` ancestry;
serialize this task after 38b/45 settle and message those peers before the first
edit. `GridPalette.swift`/`GridScene.swift` are task-45's write set — dispatch
this task only after 45 is accepted. Sizing exception: one proof-family closure
over 10 files with one verification-surface set — named for the dispatch table.

# Prerequisites

Tasks 38a (selection co-motion APIs), 38b (PianoGrid hot-file settle), and 45
(GridPalette/GridScene settle) accepted. Consumes 34a/34b's per-tab session state
(already landed).

# Interface contract

- `PianoGrid.scaleFold: Bool` (published, follows `session.scaleProjection.fold`)
  and `PianoGrid.setScaleFold(_ fold: Bool)` → `session.setScale(fold:)` — the
  roll QML lane's only fold toggle (that window mounts no transport bar).
  Published per the existing `pencilMode`/`noteSummary` pattern.
- `PianoGrid.visibleRowCount: Int` (published, read-only) =
  `session.camera.projection.visibleRowCount` — mounted row-gain/collapse
  assertions; 128 when unfolded.
- `GridPalette.scaleHighlight == "#33B595FC"` — the fork `#b595fc` at α 51/255
  (0x33) composited by the scene over the row background. `accidentalScaleHighlight`
  deletion is total: no alias, no fallback role.
- `GridScene.rebuildStatic`: a scale-member row appends exactly one highlight
  rect with `fillColor: p.scaleHighlight`; non-member rows keep only the
  existing accidental/separator lanes; rects stay inside the plot width
  (keyboard column untouched); notes keep painting above row rects.
- New check anchors (message-anchored, one per fork clause; existing S-row
  messages stay verbatim — no predicate deleted without replacing its clause):
  - swiftcore `scale_editing.swift`: "folded out-of-range Up records no edit",
    "folded out-of-range Up keeps the top scale pitch in place", "one undo
    restores a folded nudge pass", "fold edits restore the fixture MIDI bytes",
    "scale view changes push no history entry", "fold refuses a draw into an
    off-scale exception row", "fold exception-row piano key auditions its
    pitch", "fold-on edits expose the newly occupied pitch", "fold occupancy
    appears after add", "fold layout shrinks after delete", "fold layout
    restores after redo", "selected-track change preserves Fold and leaves
    Highlight off", "fold horizontal move keeps the exception pitch".
  - swiftcore `static/geometry.swift`: "production fold row count equals
    selected-track occupancy", "production fold visibility exactly matches
    occupancy", "production fold exposes an occupied off-scale pitch after
    add", "production fold keeps the unused off-scale octave hidden",
    "production fold hides every unused off-scale pitch", "highlight view
    passes leave history and bytes unchanged".
  - swiftcore `session_editor_semantics.swift`: "a fresh tab defaults to C
    major with Highlight and Fold off", "scale state stays with its tab",
    "track selection preserves per-tab scale state", "deleting a track
    preserves the tab's scale state", "undo restores scale state across a
    deleted track".
  - `tst_ShellGridInput.qml`: "mounted Up moves the selection one fold degree",
    "mounted Shift+Up moves the selection an octave in fold", "mounted chromatic
    Up moves the selection a semitone with fold off", "mounted fold Up moves an
    off-scale exception to the next degree".
  - `tst_ShellTransport.qml` (extends S186's test): "new tab opens with
    Highlight and Fold off", "Highlight toggles off and on from the transport
    control", "the first tab keeps its scale state after second-tab edits".
  - `tst_SwiftRollSelection.qml`: "fold gains the occupied off-scale row", "fold
    drag grabs the off-scale note without rebuilding rows", "fold drag commits
    the note to its scale degree", "fold collapses the off-scale row after the
    drag commit".
  - `tst_SwiftRollPlots.qml`: "Highlight tints the scale row at the fork
    composite", "Highlight leaves the non-scale row untouched", "Highlight
    leaves the keyboard column untouched", "Highlight tints every scale degree
    identically", "changing the scale root moves the Highlight lane", "changing
    the scale type moves the Highlight lane", "Highlight tints a visible
    occupied Fold row", "Highlight leaves the painted note face unchanged".
    Expected composite = `round((0xB5*51 + bg*204 + 127)/255)` per channel
    (same blend shape as the task-43 flash math; α constant 51/255 in the check
    only, never QML).

# Implementation steps

1. Swiftcore predicates first (RED only where behavior is absent — expected
   only for the tint). `scale_editing.swift` gains the swiftcore anchors
   above: fold-ON boundary pass at pitch 127; one `undoDocument` restoring a
   pressed pass (`restoreDocument` helper); view-toggle no-history pass over
   `setScale(root:/type:/highlight:/fold:)` + `selectPrimaryTrack`; draw-gate
   probe via `beginPointer` at the exception row's projection Y; `onAudition`
   capture around `beginKeyboardPointer`/`updateKeyboardPointer`; occupancy
   lifecycle via `session.camera.projection.visibleRowCount` across add →
   delete → undo → redo; fold-on-then-edit; highlight-off track switch; fold-on
   horizontal move. `static/geometry.swift`: production-bound fold rows driven
   through `session.setScale(fold:)` + live `addNotes`/`deleteNotes`; highlight
   no-history/bytes messages.
2. `PianoGrid` published accessors (contract above; no other change).
3. Palette + scene uniform tint; record RED→GREEN — the mounted tint probe and
   any note-visuals lane baseline must fail on the two-tone ink before and pass
   after; re-run `shell-note-visuals` if its baselines pin the old colors.
4. `session_editor_semantics.swift` per-tab block: two fixture sessions; assert
   defaults on both; set root/type/highlight/fold on A; B stays default and A
   survives B's edits; `selectPrimaryTrack` preserves; `document.deleteTrack` +
   `undoDocument` preserves (A044–A053 semantics).
5. `tst_ShellTransport.qml` defaults/toggle-cycle/final asserts inside the
   existing test (S186 anchors unchanged).
6. `tst_ShellGridInput.qml`: in `test_focusedRouting` shape — select a note,
   click `transportScaleFold` (findChild from the shell), `forceActiveFocus` the
   roll, `keyClick` Up / Shift+Up / fold-off Up; repeat with an off-scale
   exception note; assert pitches via `noteSummary` and undo-count via
   `appliedRevisionText` stability for the boundary case.
7. Roll lane: `tst_SwiftRollSelection.qml` drag law (add the off-scale note with
   fold off, enable `grid.setScaleFold(true)`, assert `visibleRowCount` +1,
   press/move on the note asserting mid-drag `visibleRowCount` and pitch
   unchanged, release on the adjacent scale row asserting the degree commit and
   the collapsed row count); `tst_SwiftRollPlots.qml` tint probes per contract
   (fold-composed row included).
8. Run the lanes below; capture RED→GREEN evidence for the tint family.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — all new scale_editing/
  session_editor_semantics predicates + regressions.
- `deno task verify --filter swiftcore --qt projectSession --verbose` — geometry
  production-fold rows (this is the scale_projection ledger's cited command).
- `deno task verify:shell --filter shell-grid-input --verbose` — mounted key
  delivery (the PARTIAL conjunct) + task-35 pointer regressions.
- `deno task verify:shell --filter shell-transport --verbose` — defaults/toggle/
  restore rows + S186 regression.
- `deno task verify:qml-roll --verbose` — mounted drag law + tint probes.
- Runtime prerequisite: macOS desktop host for the three QML lanes.

# Task-specific constraints

- No new C++; no code comments; no pixel constants — `#33B595FC` lives once in
  `GridPalette.swift` (the palette owner); check-side blend uses the α constant,
  never a QML literal; geometry untouched.
- Do not add fork garnish no open row pins: `ensureKeyVisible`, the transposed-
  notes announce, or chromatic-transpose audition (`pianoroll_commands.cpp:187-
  213` has them; no scale ledger row does — keyboard.cpp owns any such law).
- Do not touch scale persistence: fork state is per-tab runtime only
  (`scalecontroller.h:14-16`); PJ07 workspace restoration stays out.
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent. Ledger mapping (agent re-verifies each row against landed predicates at
  freeze; existing messages stay verbatim):
  - `proof.scale_editing.txt`: A001/A004/A007/A010 PARTIAL → mounted delivery
    anchors (upgrade, keep swiftcore anchors as the pitch conjunct);
    A002/A003/A005/A006/A008/A009/A011/A012 → undo-pass + bytes anchors;
    A013–A015 → draw-gate anchor; A016–A018 → audition anchor (+ undo/bytes);
    A019–A028 → drag-law anchors (A019 is fixture precondition — RETIRED-
    REPRESENTATION "free-pitch search branch; the Swift fixture pins the pitch
    by construction" if it cannot map); A029–A031 → fold-horizontal anchor;
    A032–A035 → fold boundary anchors.
  - `proof.scale_projection.txt`: A004/A006/A010/A011/A012 → production-fold
    anchors; A009 → RETIRED-REPRESENTATION (fixture-precondition branch);
    A015/A016/A031/A032 → highlight/history anchors (S014–S017 function anchors
    may retire per the message-anchored rule once messages execute);
    A017–A030 → tint anchors (pixel-probe rows stay MATCHED only where the
    mounted probe executes; scene-only coverage stays PARTIAL).
  - `proof.scale_fold.txt`: A003/A004/A012/A013/A017/A018/A022/A023 →
    no-history/bytes anchors; A007 → fold-on-then-edit anchor; A009 →
    highlight-off variant anchor; A014/A015/A016 → lifecycle anchors.
  - `proof.tabs_scale.txt`: rewrite the stale preamble (selector mounted at
    `TransportBar.qml:231-313`; recount the tally); A010/A011/A014/A035–A037
    stay MATCHED on S186; A012–A017 → defaults anchor; A018–A023 → mounted
    toggle-cycle anchors; A025–A034 → track-selection anchor; A038–A043 →
    tab-independence anchor (+ S186's mounted restore asserts); A044–A054 →
    delete/undo retention + final-state anchors.
- Blocked rows left untouched: any freeze-time row whose predicate cannot
  execute mounted (expected none; name any in the ledger agent's report).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — all four ledgers show executing
   message-anchored predicates and no unmapped MATCHED sites.
2. Visual (desktop): enable Highlight — uniform 20% lavender on scale rows
   only, non-scale rows/keyboard column unchanged, notes unobscured; root/type
   changes move the lanes; Fold + Highlight compose on a visible occupied row;
   drag an off-scale exception note one row — rows stay put mid-drag, the
   exception row collapses at release; compare `build-asan/porydaw.app`.
3. Keyboard smoke: select a note, fold on — Up/Down step degrees, Shift+Up jumps
   an octave, an off-scale note steps to the next member, one Cmd+Z undoes a
   whole pressed pass; per-tab: set scale state on two tabs and switch — each
   tab restores its own state and nothing is written to the project.
