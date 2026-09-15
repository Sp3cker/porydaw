# T06 — Preserve scene anchors at page-local popup sinks

## Context

Menu and pitchbend anchors arrive in window-scene coordinates, but panels now
live under a page-local overlay that may be translated inside the window. Per
[spec.md](spec.md) S5, conversion happens only at the sinks. This task also
deletes `quickengine.h` once its remaining callers (tasks 1 and 4 migrated the
rest) no longer need engine discovery. Consumes task 4's
`qmlContext()`/`overlayRoot()` session contract.

## Exact write set

- `src/ui/songview/quick/quickmenuhost.cpp`
- `src/ui/pitchbendeditor.cpp`
- `src/ui/songview/quick/quickengine.h` (deleted)

## Prerequisites

Task 4 — consumes its `QuickPopupSession::qmlContext()`/`overlayRoot()`
interface only.

## Interface contract

Per spec S5:

- Public menu anchors, `outsidePressed`, `outsideRightPressed` and note-anchor
  inputs remain window-scene coordinates; all existing caller signatures and
  global retarget conversions are preserved.
- `QuickMenuHost::createPanel` constructs panels through `session.qmlContext()`;
  panels are QObject/visual children of the popup layer so they cannot outlive
  its context.
- The root scene anchor converts once via `overlayRoot()->mapFromScene`; submenu
  origins stay overlay-local; `measureMenu`/clamping uses
  `overlayRoot()->size()`, not window size.
- `PitchBendEditor::placeContent` converts its scene note rect via
  `overlayRoot()->mapRectFromScene` and clamps to page dimensions locally; scene
  hit testing stays in scene coordinates.
- `quickengine.h` is deleted; every remaining usage migrates to explicit
  context/engine access.

Preserved: menu owners, bridge/draft APIs, and existing open/retarget entry
points.

## Implementation steps

1. Migrate `QuickMenuHost::createPanel`/`applyLevel` to session context and
   QObject ownership under the layer; convert the root anchor at the sink and
   measure/clamp against `overlayRoot()->size()`.
2. Migrate `PitchBendEditor::placeContent` to `mapRectFromScene` + local page
   clamping.
3. Remove `quickengine.h` includes/usages in this write set and delete the
   header.

## Acceptance predicate

Menus, submenus and pitchbend align and stay within a translated page with
correct outside-retarget behavior; named checks `eventviews`, `pitch-bend` and
`selectionkey` pass under the gate-A run below. Local structural inspection is
not a behavioral pass.

## Task-specific constraints

- Do not convert coordinates at producers or add a second coordinate space;
  sinks only.
- No new popup framework or anchor registry.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
