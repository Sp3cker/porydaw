# Task 3 brief — One projection in Swift

## Context

C++ `Camera::viewX` rounds content and scroll separately before subtracting
(`src/render/roll_projection.h:34-40`); Swift `EditorCamera.displayX` rounds
`(origin + tick·ppt − scrollX)·dpr` as one value
(`src/swift/app/timeline/EditorCamera.swift:233-236`) and
`PitchProjection.snappedEdge` rounds `(row·keyHeight − scrollY)·dpr`
(`src/swift/app/timeline/EditorCamera.swift:93-97`). `setHScroll` keeps
fractional scroll (`EditorCamera.swift:268-272`), so paint and Swift
hit-testing disagree by one physical pixel at straddling scrolls. This task
adopts the raster-proven order in Swift so Task 4 can port `roll_scene.cpp`
onto the same functions hit-testing uses. Decided (plan Contract §4,
`plan.md:232-245`): `displayX(tick:origin:dpr:)` becomes
`viewX(tick:dpr:)` (no `origin`); `rowTop`/`rowBottom` keep their names and
signatures and only `snappedEdge`'s body changes. Producer for Task 4.

## Exact write set

Production (formula + rename):

- `src/swift/app/timeline/EditorCamera.swift` — `displayX` → `viewX`;
  `snappedEdge` body re-expressed; reveal math (`:336-356`) retargeted.
- `src/swift/app/timeline/GridGeometry.swift` — delete `noteContentRect`/
  `noteContentBox` (`:419-436`) only if the grep in step 4 shows no
  production caller. (`noteRect`/`noteBox`, `:399-417`, need no edit:
  `rowTop`/`rowBottom` keep their names.)
- `displayX` → `viewX` at: `src/swift/app/roll/PianoGrid+SceneSync.swift`
  (`:247-249` hit zone), `src/swift/app/roll/PianoGrid+Gestures.swift`
  (`:105-106` band intersection), `src/swift/app/pitchbend/
  PitchBendPresenter.swift` (`:105-106` anchors), `src/swift/app/drawer/
  voicechanges/VoiceChangesScene.swift` (`:158` `xForTick`),
  `src/swift/app/drawer/automation/AutomationProjection.swift` (`:143-147`
  `x` duplicates the old snap order inline — delegate to the camera),
  `src/swift/app/drawer/automation/AutomationContentPublication.swift`
  (`:81`).
- Verify-only, no edit expected: `GridScene.swift:157-160` (row calls keep
  names), `tickAtContentX`-only callers (`GridGesture.swift:115-180`,
  `PianoGrid+Gestures.swift:155,289,423-424`, `PlayheadGuides.swift:120-123`,
  `RulerMenuPresenter.swift:108-340`), `AutomationOverlayPublication.swift`,
  `AutomationDrawingContent.swift`, `VoiceChangesProjection.swift:383`
  (consume `projection.x/y` or an injected closure — unchanged),
  `VelocityProjection.swift:34-47` (`stableXForTick` uses `contentTickX` and
  `scrollOffsetX` already rounds scroll alone; comment wording only),
  `VoiceChangesScene.swift:252-255` (`contentTickX` label projection —
  unchanged), `PianoGrid+Support.swift` (no projection symbol — excluded).

Checks (plan table row 3: every check file calling `displayX`/
`noteContentRect`/`noteContentBox` — mechanical rename only, assertions
unchanged — plus `camera.swift`):

- Mechanical `displayX` → `viewX`: `src/checks/rollcheck/selection.swift:
  16-17`, `EditorGridProjectionChecks.swift:134,202-203`,
  `keyboard.swift:186-195,209-231`, `pencil.swift:48-52,423-424`,
  `resize.swift` (`:52-55,104-111,142-143,169-183,226-230,245-248,293-321,
  428-444`), `selection_editing.swift:235-236`,
  `static/geometry.swift:131-138`, `src/checks/drawerpresentation/
  VoiceChangesPageChecks.swift:140`, `velocity_context.swift:100-109`,
  `voice_picker.swift:147`, `voicemenus.swift:173-174`.
- Migrate `noteContentBox` → `noteBox`: `keyboard_time_selection.swift:
  47-50`, `note_rendering_support.swift:102-106` (exact: `viewportPoint`,
  `:110-114`, already subtracts the rounded scroll the content box omits).
- Assertion change: `src/checks/rollcheck/static/camera.swift:39-40,231-240`
  re-pinned to the unified formula (step 5).
- Affected `proof.*.txt` rows in the same commit (step 6).

## Prerequisites

- Task 1 interfaces (`DisplayListWriter`, wire header): only to avoid
  colliding on `GridGeometry.swift` helper names; no behavior consumed.
- `deno task lsp:swift` has been run after the last CMake reconfigure
  (plan Global Constraints), before any rename.

## Interface contract

- `EditorCamera.viewX(tick: Double, dpr: Double) -> Double` is
  `contentTickX(tick, dpr: dpr) − (scrollX·dpr).rounded()/dpr`, with the same
  non-finite-`dpr` guard `displayX` has today (`EditorCamera.swift:233-236`).
  The `origin` parameter is deleted; all production callers pass `0` today
  except the check at `camera.swift:39`, which is re-pinned.
- `PitchProjection.rowTop`/`rowBottom` keep their names and signatures;
  only the private `snappedEdge` body changes to the two-term rounded
  difference `(content·dpr).rounded()/dpr − (scrollY·dpr).rounded()/dpr`.
- `contentX(tick:)` (`:231`), `tickAtContentX` (`:232`), `contentTickX`
  (`:238-240`), `contentRowTop`/`contentRowBottom` (`:64-70`) are unchanged.
- Reveal (`ensureTickVisible`, `ensureRangeVisible`,
  `EditorCamera.swift:336-356`): visibility tests use `viewX`; the new
  scroll value stays unrounded content math
  (`tick·ppt − viewport·fraction`, `scrollX + delta`) because `setHScroll`
  keeps fractional scroll by design (`:268-272`). `ensureKeyVisible`
  (`:358-366`) is unrounded row math and is unchanged.
- Drawer result: `AutomationProjection.x` returns exactly
  `camera.viewX(tick: Double(tick), dpr: bounds.devicePixelRatio)`; its
  `contentX` stays the unsnapped `camera.contentX`.

## Implementation steps

1. Rewrite `displayX` as `viewX` with the unified formula; rewrite the
   `snappedEdge` body as the two-term rounded difference under the
   unchanged `rowTop`/`rowBottom` signatures. Delete `displayX` only.
2. Retarget the production `displayX` callers (write set above) to `viewX`;
   replace the inline snap in `AutomationProjection.x` (`:143-147`) with
   the camera call. Verify-only files: read each cited range and leave
   unchanged.
3. Reveal: `ensureTickVisible`/`ensureRangeVisible` compare with `viewX`
   but compute the replacement scroll from `contentX`/unrounded arithmetic
   as today; do not round the value passed to `setHScroll`.
4. Grep `noteContentRect|noteContentBox` under `src/swift` and `src/checks`:
   verified pre-freeze callers are definitions
   (`GridGeometry.swift:419-436`) plus `keyboard_time_selection.swift:47-50`
   and `note_rendering_support.swift:102-106`. Migrate those two checks to
   `noteBox` and delete both helpers; if the grep finds a production
   caller, keep them and migrate that caller instead.
5. Re-pin `camera.swift:39-40` to `viewX(tick:dpr:)` with the two-term
   expectation, and `:231-240` to expect
   `contentTickX − round(scroll·dpr)/dpr` per `(tick, dpr)` case (origin is
   gone; the `0.25`-origin loop collapses to one case per tick). Keep
   `setHScroll`-fractional assertions (`:33-38`) unchanged.
6. Grep each changed message text under `src/checks/**/proof.*.txt`
   (known anchors: `proof.clipboardchecks.txt` S026-S030 for
   `EditorGridProjectionChecks.swift` messages; no rows currently anchor
   `camera.swift` messages). Where an assertion class genuinely changes,
   repair the anchor with `deno task proof:edit` in the same commit; where
   only the formula name in code changed but the message is identical,
   leave the row untouched.

## Acceptance predicate

- Every lane on this commit alone, before Task 4 is dispatched:
  `deno task checks --filter swiftcore --verbose` (re-pinned camera
  assertions, projection parity, economy, roll semantics),
  `deno task checks:qml-roll --verbose`, `deno task checks:qml --verbose`,
  `deno task checks:shell --verbose` (hit-test journeys that click computed
  points — plan Open risk 3: fix the check's point, not the formula).
- Rasters byte-identical: C++ still paints, so any raster diff in this task
  is a defect. This separates Task 3 (hit points move ≤1 px, pixels do not)
  from Task 4 (pixels must not move either; hit points do not change again).
- `deno task proof check --executed` — covers ledger health after anchor
  repair.
- Gap: byte-level paint/hit agreement at straddling fractional scrolls is
  first asserted when Task 4 paints with the same formula.

## Task-specific constraints

- The only behavior change is the ≤1-physical-pixel hit-zone move at
  straddling scrolls (Contract §4). Any other raster or summary difference
  is a defect, not tolerance.
- Do not touch `roll_scene.cpp`, `ruler_scene.cpp`, `timeline_renderer.cpp`,
  QML, or the `TimelineRenderer` bindings; C++ keeps painting from its own
  copy until Task 4.
- Mechanical renames in check files must not alter messages, tolerances, or
  ledger anchors; only `camera.swift` and its proof rows may change
  assertions.
