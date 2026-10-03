# Context

R23: the Swift roll republishes whole-note-model work on selection/highlight-only changes. `GridScene.rebuildNotes` (`src/swift/app/roll/GridScene.swift:665-730`) recomputes `displayedNote`/`noteBox`/fill for every note in every ghost pass, culling only after box compute; `PianoGrid.refreshNotes`/`recomputeContentEndTick`/`publishOutputs` (`src/swift/app/roll/PianoGrid.swift:1063-1101,1267-1291`) re-walk every track and rebuild the `noteSummary` JSON on any refresh triggered by notes OR selection — including hover, band and timeSelection-highlight republishes. `RulerMenuPresenter.sweepTrackScope` (:308-320) is already correctly scoped (single-track fast path walks zero extra tracks) — lock it, do not rewrite it. Ghost rendering invariants are pinned by `checkGhostNotes` (S014–S022) and `checkTimeSelectionHighlights` (S076): preserve them exactly. Read plan.md Global constraints and verification.md.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`
- `src/swift/app/roll/GridScene.swift`
- `src/checks/rollcheck/note_rendering.swift`
- `src/checks/rollcheck/EditorGridCameraChecks.swift`
- `src/checks/rollcheck/proof.note_rendering.txt`

# Prerequisites

None. `sweepTrackScope` check rows (proof.keyboard.txt S072/S073 timelineRulerScope) already exist. `DocumentProjectionCache`/`ScaleProjection.projection` are read-only reuse — selected-track-only scoping is already correct there.

# Interface contract

- Split the rebuild so selection/timeSelection/hover-only changes never recompute note boxes or fills: fills/boxes are a function of (document revision, camera, fonts/track set); borders/rings/highlights are a function of (selection, timeSelection, hover) over already-computed geometry. After the split, a selection-only refresh publishes identical `pianoNoteFills` (count and contents) while only border/selection output changes.
- Cull before projecting: compute the visible tick range and visible pitch set once per rebuild (existing `visibleTicks`) and skip `displayX`/`noteBox` for off-view notes. Ghost notes cull by the same viewport test already applied — their fill identity (`PaletteMath.ghostFill(track:accidentalRow:)`) must stay a pure function so it is cache-safe.
- `noteSummary` republishes only when the underlying note set/selection content changes — extend the existing `notes != summaryNotes` guard so camera-only, hover-only and highlight-only refreshes produce a byte-identical summary string with no rebuild.
- Add `@QtIgnored` observability counters (e.g. `boxesProjected`/`fillWrites` on `GridScene`, `noteSummaryRebuilds` on `PianoGrid`), resettable per check, so predicates can assert zero fill/summary work on selection-only refreshes. Counters must not affect publication behavior.
- Ghost invariants preserved byte-for-byte: non-selected tracks project `ghost:true`; `setTrack` swaps roles; ghosts get no border/selection ring except via `timeCovers` scope; no ghost labels; `hitNote` skips ghosts; whole-document model content unchanged.

# Implementation steps

1. Add the counters and the viewport-cull-before-project change in `GridScene.rebuildNotes` (compute `visibleTicks`/visible pitch once; skip projection for off-view notes; keep fold's `hiddenRow` ghost-skip order).
2. Split fill/box computation from border/ring/highlight emission so the selection pass reuses computed geometry; keep `ghostPass` ordering and `timeCovers` scoping identical.
3. Guard `recomputeContentEndTick`/`publishOutputs` so selection-only and highlight-only refreshes skip the all-track walks and the `noteSummary` rebuild.
4. Extend `note_rendering.swift`/`EditorGridCameraChecks.swift` with predicates: selection-only refresh → identical fills + zero counter growth; hover/highlight refresh → `noteSummary` string identical (extend the camera-invariance assertion pattern at EditorGridCameraChecks.swift:~284-288); `sweepTrackScope` single-track fixture → scope == {primary} with zero `notes(in:)` calls for other tracks.
5. Ledger: in `proof.note_rendering.txt` only rows these predicates execute may move (message anchors required); pixel/frame-cadence clauses (A009–A013 in swiftrollbench, A016 raster, A029/A053 framebuffer rings) stay GAP — presenter predicates cannot claim them.

# Acceptance predicate

Selection/highlight/hover refreshes perform zero fill recomputation and zero `noteSummary` rebuilds; all prior ghost/selection predicates still execute; `sweepTrackScope` locked by an executed predicate.

Controller-run named checks after the writer freezes:
- `deno task verify --filter swiftcore --verbose` — note_rendering/camera/sweep predicates + regression.
- `deno task verify:qml-roll --verbose` — rendered noteSummary/renderedNoteCount/ghost-face regression guards.
- `deno task proof check --executed` and `deno task proof check --strict-mappings`.

# Task-specific constraints

Do not touch `RulerMenuPresenter.swift`, lifecycle/cancel paths in `PianoGrid` (R16/R26 territory), or the automation-drawer sweep vocabulary (different surface). This is a behavior-preserving projection-economy change: identical published outputs for identical inputs, minus redundant recomputation. If an invariant cannot be preserved without keeping a recompute, keep the recompute and report the constraint — never drop correctness for the metric.
