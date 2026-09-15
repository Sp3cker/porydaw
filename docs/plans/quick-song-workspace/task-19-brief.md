# T19 — Prove real tab controls and model invariants

## Context

Gate B's behavior proof for the collection cutover: existing workspace
tab/session checks are migrated off QTabWidget-specific lookup onto the real
Quick strip and projected model. Consumes the frozen interfaces of tasks 13
(model), 14 (strip objectNames/controls), 15 (host), 16 (WorkspaceUi
operations), 17 (window-free sessions). Its scenarios are what task13's
acceptance defers to.

## Exact write set

- `src/checks/workspace/tst_workspacesessions.h`
- `src/checks/workspace/tabs_lifecycle.cpp`
- `src/checks/workspace/tabs_persistence.cpp`

## Prerequisites

Interfaces from tasks 13–17.

## Interface contract

Produces check scenarios per spec S2/S8; no production interface. Requirements:

- Replace QTabWidget-specific title lookup with the displayed Quick
  title/accessible state; preserve the existing dirty, close, replacement, and
  restore test scenarios.
- QAbstractItemModelTester attached to the actual projected SongTabsModel.
- Real input paths: click close/switch through the real tab controls
  (`songTab:<songKey>`, `songTabClose:<songKey>`), in-strip drag reorder, and
  outside/cancel/disabled drops that must not reorder; overflow wheel + click
  exposes offscreen tabs.
- Stable scene/camera/selection/undo across A/B/A switching and reorder, with
  persisted order matching actual vector order.
- All notifications exercised through real WorkspaceUi operations — no
  model-private hook.

## Implementation steps

1. Update tst_workspacesessions.h fixture declarations for the window-free
   session/host shape (QuickSceneHost per spec S8 where a standalone session
   needs a page).
2. In tabs_lifecycle.cpp: migrate title/accessible-state lookup to the Quick
   strip; add model tester; cover real click switch/close, dirty-close
   cancellation, replacement, background open, and selected-close
   successor/audio ordering per S2.
3. In tabs_persistence.cpp: cover reorder persistence (vector order persisted),
   restore, closed-load tombstones, and A/B/A retention of page QObject, camera,
   selection, undo.
4. Add drag/drop coverage: valid released drop inside viewport over an actual
   tab reorders; CancelGrabExclusive, disabled-mid-drag, outside release, and
   close-button press never reorder; no stale drop index.
5. Remove assertions pinning old per-song window destruction or QWidget identity
   rather than repinning them.

## Acceptance predicate

All real tab behavior including dirty-cancel and reorder persistence is correct.
NAMED CHECKS: `deno task verify --filter tabcheck --filter sessioncheck`
(controller-run at gate B).

## Task-specific constraints

- Extend existing harnesses only; no new test catalog or standalone executable.
- No field-copy, wiring, or source-text assertions substituted for real behavior
  checks.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
