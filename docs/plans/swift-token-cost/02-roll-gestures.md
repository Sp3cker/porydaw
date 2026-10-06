# Plan 02 — Roll gestures + scene sync (planner: StripedLeopard — COMPLETE)

## Verdict

PARTIALLY VERIFIED. Co-load claim TRUE (slightly understated), but win comes from a NARROWER
consolidation than "unified gesture→scene module": ONE gesture-side module
(state machine + input mapping + preview projection). Absorbing the scene-sync sink does NOT cut tokens.

## Evidence

One left-drag move co-loads ~5 files / ~1631 lines:
QML `EditorRollBand.qml:125-238` → `PianoGrid.swift:335` wrapper →
`PianoGrid+Gestures.swift:258-306 updatePointerImpl` (state in `PianoGrid.swift:47-99`) →
`GridGesture.swift:95-210` state machine → `refreshNotes()` →
`PianoGrid+SceneSync.swift:82-100 sceneInput() :15-70` → `GridSceneInput`
(`GridScene+Rebuild.swift:7-38`) → `GridScene+Notes.swift:11-25/47-82` rebuild.
Counts (wc -l): PianoGrid 423, +Gestures 512, GridGesture 211, +SceneSync 393, +Rebuild 92.

Coupling facts:
- GridGesture is module-internal (roll/ only, zero QML/QtBridge/test refs; @QtIgnored storage).
- Every `GridGesture.updated()` call site lives in +Gestures — inseparable pair split across two files.
- COUNTER-EVIDENCE vs full unification: refreshNotes/sceneInput is a SHARED sink with 5+ non-gesture
  producers (Support.swift:95,120,125,136,168; PianoGrid.swift:225,279,315; SceneSync:73-79,103-151).
  Moving the sink into a gesture module is token zero-sum + worse cohesion, and contradicts
  `docs/plans/swift-feature-parity/split-600-wave.md:390` (+SceneSync owns session projection/publication).
- Stranded gesture-facing members in SceneSync: displayedNote :256-282, currentStatusText :327-352,
  pitch(atY:) :248-253, hitZone :287-305, hitNote :308-324.

Token delta: dominant gesture-task class 1539 lines/4 files → ~852 lines/1 file + targeted sceneInput
read (~56 lines) ≈ −40–45% co-loaded context. Camera/publication tasks unchanged. Net: clear reduction,
zero behavior change (pure moves between extensions of same class, same module/target).

## Preservation constraints

- QML slot names/signatures frozen (`EditorRollBand.qml:162-235`; frozen family
  `src/checks/editorqml/tst_ShellGridInput{,Draw,Editing,Cancel,Keyboard,Automation}.qml`).
- QtBridge surface stays in PianoGrid.swift (@QtBridgeable, @QtTracked, @QtSignal).
  Moved members are @QtIgnored internal extensions — file-layout agnostic codegen (existing precedent).
- Scene seam untouched: GridSceneInput shape, rebuild*/displayList/displayRevision/hoverChip*,
  content-tier caching invariants (contentGeneration, builtProjection, RollDisplayFrameKey equality).
- Behavior: gesture transition table, commitGesture, left/right interlock, band audition bookkeeping,
  cancel routes; Swift checks read `grid.drawPreview`, `grid.interactionActive` — internal names preserved.
- Honors split-600-wave.md:388 (left/right gesture in one owner) and :390 (SceneSync single rendering owner).

## Steps

1. Fold `GridGesture.swift` (1-211) into `PianoGrid+Gestures.swift` above the extension block.
   Delete the file; remove its line from `src/swift/app/CMakeLists.txt:62`. Pure move.
   Result: 723-line gesture module owning state machine + orchestration.
2. Move gesture-facing members SceneSync → gesture module: pitch(atY:) :248-253, hitZone :287-305,
   hitNote :308-324, displayedNote :256-282, currentStatusText :327-352. SceneSync retains
   sceneInput/rebuildScene/refreshNotes/refreshCameraPresentation*/publishGeometry/publishOutputs/
   fetchNoteSummary/defaultVerticalScroll/recomputeContentEndTick/updateTypography (~200 lines, pure seam).
   Result: ~852-line gesture module (x/y → hit-test → state → preview → status); handoff at refreshNotes()/sceneInput().
3. Keep filename `PianoGrid+Gestures.swift` (no rename). Update top comment to state module contract.
4. Gate: steps 1+2 independently shippable pure-move commits. If ~852 lines judged too large
   (roll's largest; RollPlotBuilder is 564), ship step 1 only — captures state-machine co-load win (4→3 files).
5. Verify (no test edits): `checks:shell --filter shell-grid-input`, `--filter shell-grid`,
   `checks:qml-roll`, `checks:bridge`, full `checks` (rollcheck lanes: resize, selection_*, interlock,
   pencil, note_rendering_velocity, EditorGridProjectionChecks). Note: split-600-wave.md cites `verify:*`
   aliases that no longer exist; live names are `checks:*`.

## Risks

- ~852 lines exceeds split-600-wave.md:388 band; document deviation (step-1-only fallback).
- CMakeLists omission breaks build (:62 one-line edit).
- Closed move list (5 members only) — recomputeContentEndTick/updateTypography MUST stay in SceneSync.
- No QML/test risk (internal members; public names, tracked props, GridSceneInput unchanged).
- Bridge regen nil-by-precedent; still gated by checks:bridge.

## Non-goals

- Do NOT absorb sceneInput()/refreshNotes()/rebuildScene into gesture module.
- Do NOT extract gesture state into a new context/controller object (forbidden by :388).
- Do NOT touch GridScene*/RollPlotBuilder/RollKeyboardBuilder/RollRulerBuilder/RollDisplayLists/SceneRectPacking.
- Do NOT rename public slots/tracked props or alter GridGesture semantics. No reformatting beyond format.
- No ledger reconciliation; no new tests.

## Assumptions

- Extension relocation within same module/target is bridge-neutral (evidenced by current Impl-in-extension layout).
- wc -l counts as above; line numbers cite current HEAD — re-anchor before execution.
