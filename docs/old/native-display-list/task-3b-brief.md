# Task 3b brief — One projection formula (the plan's only behavior change)

## Context

Task 3a settled the names (`viewX(tick:dpr:)`, no `origin`) with zero value
change. The drift remains: Swift rounds content-minus-scroll as one value
while C++ `Camera::viewX` rounds `contentTickX` and the scroll origin
separately and subtracts (`src/render/roll_projection.h:34-40`).
`setHScroll` keeps fractional scroll (`EditorCamera.swift:268-272`), so the
two orders differ by one physical pixel whenever the fractional parts
straddle `.5`, and Swift hit-testing disagrees with the painted note at
those scrolls. This task adopts the raster-proven order in Swift —
`round(content·dpr)/dpr − round(scroll·dpr)/dpr` — in the bodies of
`EditorCamera.viewX` and `PitchProjection.snappedEdge`, and re-pins the
camera checks to the unified formula. Consumer: Tasks 4a/4b, which port
the roll scenes onto these same functions. This is the only behavior
change in the plan (plan Contract §4, `plan.md:265-278`).

## Exact write set

- `src/swift/app/timeline/EditorCamera.swift` — `viewX` body
  (`:233-236`) and `snappedEdge` body (`:93-97`) only. Signatures
  untouched (`rowTop`/`rowBottom` keep names and signatures, `:59-62`).
- `src/checks/rollcheck/static/camera.swift` (`:39-40,231-240` — re-pinned
  to the unified formula; see steps).
- The `proof.*.txt` file(s) anchoring `camera.swift` messages, repaired
  with `deno task proof:edit` in the same commit — find them by grepping
  `camera.swift` under `src/checks/**/proof.*.txt`. Expect possibly none:
  on 2026-09-28 no ledger row contains `camera.swift` or the camera
  assertion message texts (`physical-pixel affine projection`, `display
  projection snaps to a physical pixel`); if the grep is still empty,
  there is nothing to repair and the commit carries no ledger edit.

Closed set: no other file may be edited. In particular
`AutomationProjection.x` already delegates to `viewX` (Task 3a) and picks
up the new order with no edit; `rowTop`/`rowBottom` callers
(`GridScene.swift:157-160` and the ~20 check callers) need no edit.

## Prerequisites

- Task 3a interfaces: `viewX(tick:dpr:)`, origin-free callers, deleted
  `noteContentRect`/`noteContentBox`. No Task 1 behavior consumed.

## Interface contract

- `EditorCamera.viewX(tick:dpr:)` is `contentTickX(tick, dpr: dpr) −
  (scrollX·dpr).rounded()/dpr`, with the same non-finite-`dpr` guard it
  has today (`EditorCamera.swift:233-236`).
- `PitchProjection.snappedEdge` (`EditorCamera.swift:93-97`) is the
  two-term rounded difference `(row·keyHeight·dpr).rounded()/dpr −
  (scrollY·dpr).rounded()/dpr`; `rowTop`/`rowBottom` signatures unchanged.
- `contentX(tick:)` (`:231`), `tickAtContentX` (`:232`),
  `contentTickX` (`:238-240`), `contentRowTop`/`contentRowBottom`
  (`:64-70`) are unchanged.
- Reveal math (`ensureTickVisible`/`ensureRangeVisible`,
  `EditorCamera.swift:336-356`) tests visibility with `viewX` and keeps
  its unrounded `contentX` scroll replacement (`:340`, `:345`,
  `:351-355`); the value passed to `setHScroll` is never rounded.

## Implementation steps

1. Rewrite the `viewX` body as the contract's two-term difference under
   the unchanged signature; rewrite the `snappedEdge` body as the
   two-term rounded difference under the unchanged `rowTop`/`rowBottom`
   signatures.
2. Re-pin `camera.swift:39-40` to `viewX(tick:dpr:)` with the two-term
   expectation (origin is gone; the `0.2`-origin case becomes the
   equivalent scroll-fractional case under the unified formula), and
   `:231-240` to expect `contentTickX − round(scroll·dpr)/dpr` per
   `(tick, dpr)` case — the `0.25`-origin loop collapses to one case per
   tick. Keep `setHScroll`-fractional assertions (`:33-38`) unchanged.
   Repair the changed message texts' ledger rows with `deno task
   proof:edit` in the same commit (exact write set above).
3. Leave the inverse-projection loop (`:241-262`) structurally intact;
   adjust only what the unified formula forces (the `origin` subtraction
   in `:253` dies with the parameter; tolerance stays as-is unless the
   lane proves otherwise — a widened tolerance is a defect, not a fix).

## Acceptance predicate

- Every lane green on this commit alone (checkpoint 1b): `deno task
  checks --filter swiftcore --verbose` (re-pinned camera assertions,
  projection parity, economy, roll semantics), `deno task checks:qml-roll
  --verbose`, `deno task checks:shell --verbose` (hit-test journeys that
  click computed points — plan Open risk 3: fix the check's point, not
  the formula), `deno task checks:qml --verbose`.
- Rasters byte-identical: C++ still paints, so any raster diff in this
  task is a defect. Hit points move ≤ 1 physical pixel, only at
  straddling fractional scrolls.
- `deno task proof check --executed` — covers ledger health after anchor
  repair.
- Gap: byte-level paint/hit agreement at straddling fractional scrolls is
  first asserted when Task 4a paints with the same formula.

## Task-specific constraints

- The only behavior change is the ≤ 1-physical-pixel hit-zone move at
  straddling scrolls (Contract §4). Any other raster or summary
  difference is a defect, not tolerance.
- Do not touch `roll_scene.cpp`, `ruler_scene.cpp`,
  `timeline_renderer.cpp`, QML, or the `TimelineRenderer` bindings; C++
  keeps painting from its own copy until Task 4a.
- Only `camera.swift` and its proof rows may change assertions; a failing
  shell check that clicked a computed point is fixed at the check's
  point, never by adjusting `viewX`/`snappedEdge` (plan Open risk 3).
