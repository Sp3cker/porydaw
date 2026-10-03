# Task 3a brief — Projection rename (no behavior change)

## Context

Swift owns the projection formulas that Task 3b will unify (plan Contract
§4, `plan.md:265-278`) and that Tasks 4a/4b will port the roll scenes onto.
Before any value may move, the names must settle: `EditorCamera.displayX`
rounds `(origin + tick·ppt − scrollX)·dpr` as one value
(`src/swift/app/timeline/EditorCamera.swift:233-236`) and carries an
`origin` parameter whose only non-zero caller is the check at
`src/checks/rollcheck/static/camera.swift:39`. C++ `Camera::viewX` already
uses the `viewX` name for the raster-proven order
(`src/render/roll_projection.h:34-40`). This task renames Swift
`displayX(tick:origin:dpr:)` to `viewX(tick:dpr:)`, deletes the `origin`
parameter, deletes the check-only `GridMetrics.noteContentRect`/
`noteContentBox` helpers, and mechanically retargets every caller with
zero value change. Producer for Task 3b (the formula change) and
Tasks 4a/4b.

## Exact write set

Production (rename only; bodies compute identical values):

- `src/swift/app/timeline/EditorCamera.swift` — definition
  (`:233-236`) renamed; internal call sites retargeted (`:338`, `:348-349`).
- `src/swift/app/timeline/GridGeometry.swift` — delete `noteContentRect`
  (`:419-430`) and `noteContentBox` (`:432-436`); `noteRect`/`noteBox`
  (`:399-417`) unchanged.
- `src/swift/app/roll/PianoGrid+SceneSync.swift` — hit-zone call site
  (`:253-255`).
- `src/swift/app/roll/PianoGrid+Gestures.swift` — band-intersection call
  site (`:105-106`).
- `src/swift/app/pitchbend/PitchBendPresenter.swift` — anchor call sites
  (`:105-106`).
- `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift` — `xForTick`
  (`:158`).
- `src/swift/app/drawer/automation/AutomationProjection.swift` — `x`
  (`:143-147`) delegates to the camera instead of its inline snap.
- `src/swift/app/drawer/automation/AutomationContentPublication.swift`
  (`:81`).

Checks (mechanical rename only; messages, tolerances, anchors unchanged):

- `src/checks/rollcheck/selection.swift` (`:16-17`).
- `src/checks/rollcheck/EditorGridProjectionChecks.swift` (`:134,202-203`).
- `src/checks/rollcheck/keyboard.swift` (`:186-195,209-231`).
- `src/checks/rollcheck/pencil.swift` (`:48-52,423-424`).
- `src/checks/rollcheck/resize.swift`
  (`:52-55,104-111,142-143,169-183,226-230,245-248,293-321,428-444`).
- `src/checks/rollcheck/selection_editing.swift` (`:235-236`).
- `src/checks/rollcheck/static/geometry.swift` (`:131-138`).
- `src/checks/rollcheck/static/camera.swift` (`:39,235,252` — call sites
  rewritten, assertion text unchanged; see steps).
- `src/checks/rollcheck/keyboard_time_selection.swift` (`:47-50`,
  `noteContentBox` → `noteBox`).
- `src/checks/rollcheck/note_rendering_support.swift` (`:102-106`,
  `noteContentBox` → `noteBox` with `contentTickX` x-inputs as today).
- `src/checks/drawerpresentation/VoiceChangesPageChecks.swift` (`:140`).
- `src/checks/drawerpresentation/velocity_context.swift` (`:100-109`).
- `src/checks/drawerpresentation/voice_picker.swift` (`:147`).
- `src/checks/drawerpresentation/voicemenus.swift` (`:173-174`).
- Affected `proof.*.txt` rows whose anchors are path/line only, repaired
  with `deno task proof:edit` in the same commit (expect none: a scoped
  grep for `camera.swift` and the camera assertion message texts under
  `src/checks/**/proof.*.txt` hits nothing on 2026-09-28).

Verify-only, no edit: `GridScene.swift:157-160`,
`GridGesture.swift:115-180`, `PianoGrid+Gestures.swift:155,289,423-424`,
`PlayheadGuides.swift:120-123`, `RulerMenuPresenter.swift:108-340`,
`AutomationOverlayPublication.swift`, `AutomationDrawingContent.swift`,
`VoiceChangesProjection.swift:383`, `VelocityProjection.swift:29-33`
(`stableXForTick` uses `contentTickX`; only the `displayX` word in its
comment is refreshed), `VoiceChangesScene.swift:252-255`
(`contentTickX` label projection), `PianoGrid+Support.swift` (no
projection symbol), `VoiceChangesProjection.swift:259` and
`VoiceLanePolicy.swift:106-112` (`displayX` closure parameter names —
local identifiers, not the camera method; leave them).

## Prerequisites

- `deno task lsp:swift` has been run after the last CMake reconfigure
  (plan Global Constraints), before any rename.
- Task 1 interfaces (`DisplayListWriter`, wire header): only to avoid
  colliding on `GridGeometry.swift` helper names; no behavior consumed.

## Interface contract

- `EditorCamera.viewX(tick: Double, dpr: Double) -> Double` computes
  exactly what `displayX(tick:origin:dpr:)` computed at `origin == 0`:
  `((tick·ppt − scrollX)·dpr).rounded()/dpr`, with the same
  non-finite-`dpr` guard (`EditorCamera.swift:233-236`). The `origin`
  parameter is deleted; `displayX` is deleted.
- `PitchProjection.rowTop`/`rowBottom`/`snappedEdge`
  (`EditorCamera.swift:59-62,93-97`), `contentX(tick:)` (`:231`),
  `tickAtContentX` (`:232`), `contentTickX` (`:238-240`),
  `contentRowTop`/`contentRowBottom` (`:64-70`) are unchanged.
- `AutomationProjection.x` returns exactly
  `camera.viewX(tick: Double(tick), dpr: bounds.devicePixelRatio)`; its
  `contentX` stays the unsnapped `camera.contentX`
  (`AutomationProjection.swift:139`).
- Check-only origin-bearing call sites (`camera.swift:39,235,252`) inline
  the old single-round expression `((origin + contentX)·dpr).rounded()/dpr`
  so every asserted value is bit-identical; assertion message texts are
  byte-identical.

## Implementation steps

1. Rename `displayX` to `viewX` with the `origin` parameter deleted, body
   unchanged apart from dropping `origin +`. Use `xd://lsp` rename where
   possible; delete `displayX` only.
2. Retarget the production `displayX` callers in the write set to `viewX`;
   replace the inline snap in `AutomationProjection.x`
   (`AutomationProjection.swift:143-147`) with the camera call. Read each
   verify-only file at its cited range and leave it unchanged.
3. Reveal (`ensureTickVisible`, `EditorCamera.swift:336-341`;
   `ensureRangeVisible`, `:343-356`): retarget the three `displayX` uses
   (`:338`, `:348-349`) to `viewX`; the replacement scroll values stay
   unrounded content math (`:340`, `:345`, `:351-355`) because
   `setHScroll` keeps fractional scroll by design (`:268-272`).
   `ensureKeyVisible` (`:358-366`) is unrounded row math and is unchanged.
4. Re-run the scoped grep `noteContentRect|noteContentBox` under
   `src/swift` and `src/checks` (never root-scoped): if the only callers
   are the definitions (`GridGeometry.swift:419-436`) plus
   `keyboard_time_selection.swift:47-50` and
   `note_rendering_support.swift:102-106`, migrate those two checks to
   `noteBox` and delete both helpers; if the grep finds a production
   caller, keep them and migrate that caller instead.
5. Rewrite `camera.swift:39` to pass no origin (value preserved via the
   contract's inlined expression) without touching its message text;
   rewrite `:235` and `:252` the same way (the `0.25`-origin loop keeps
   both origins, still asserting the old single-round values). Keep the
   `setHScroll`-fractional assertions (`:33-38`) unchanged.
6. Grep each changed call site's message text under
   `src/checks/**/proof.*.txt`. Where only the formula name in code
   changed but the message is identical, leave the row untouched; repair
   path/line-only anchors with `deno task proof:edit` in the same commit.

## Acceptance predicate

- Every lane on this commit alone (checkpoint 1a — pure rename, nothing
  moved): `deno task checks --filter swiftcore --verbose` (renamed
  projection callers, roll semantics), `deno task checks:qml-roll
  --verbose` (raster identity), `deno task checks:shell --verbose`
  (hit-test journeys that click computed points), `deno task checks:qml
  --verbose` (drawer pages).
- Rasters byte-identical and every hit-test point unchanged: any pixel or
  point move in this task is a defect.
- `deno task proof check --executed` — covers ledger health after anchor
  repair.
- Gap: byte-level paint/hit agreement at straddling fractional scrolls is
  first asserted when Task 4a paints with the same formula.

## Task-specific constraints

- Zero behavior change: any raster, summary, or hit-point difference is a
  defect, not tolerance.
- Do not touch `roll_scene.cpp`, `ruler_scene.cpp`,
  `timeline_renderer.cpp`, QML, or the `TimelineRenderer` bindings; C++
  keeps painting from its own copy until Task 4a.
- Mechanical renames in check files must not alter messages, tolerances,
  or ledger anchors; no `camera.swift` assertion text changes in this
  task.
