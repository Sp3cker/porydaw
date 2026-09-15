# T17 — Make SongTab a window-free QObject session

## Context

Gate B removes SongTab's QWidget identity: it becomes a pure QObject session
(document/history/timeline/lease/staged load) with no window, engine, page item,
layout, or InputGate. Consumed by task18 (MainWindow handlers operate on
window-free sessions), task19/20 (session checks), and task22 (fixture migration
to QuickSceneHost — this task's new shape is what enables that batch). Consumes
task1's explicit scene lifecycle and task16's ownership shape (WorkspaceUi
constructs SongTab without a QObject parent; the unique_ptr owns it).

## Exact write set

- `src/ui/songtab.h`
- `src/ui/songtab.cpp`

## Prerequisites

Interfaces from tasks 1 (scene lifecycle) and 16 (owner construction/selection).

## Interface contract

Per spec S1, exactly:

- `SongTab` is `QObject` with `SongTab(SongName, QObject *parent = nullptr)`;
  WorkspaceUi constructs it without a parent.
- Retain document/history, timeline, bank lease, staged load, signals and reload
  semantics; preserve LoadEvent, the existing readiness definition, staged
  rebind, and m_view-before-document teardown order.
- Final state has no window, engine, page item, layout, or InputGate: remove the
  nested InputGate member/watch/readiness filter wiring, m_host/layout/widget
  includes, and host destruction.
- Readiness loss invokes the existing `cancelTransientInput` directly even while
  no scene is attached; the QML model `ready` role governs attached input
  eligibility (spec S4 `isInputEligible` seam).

## Implementation steps

1. Change the base class to QObject and the constructor signature to
   `SongTab(SongName, QObject *parent = nullptr)`; drop QWidget
   includes/members.
2. Remove InputGate, host member, layout/widget wiring and host destruction;
   scene attachment is owned by the page delegate/coordinator path (tasks 1/14),
   not SongTab.
3. Rewire readiness-loss handling to call `cancelTransientInput` directly; keep
   the readiness definition and its notification unchanged.
4. Verify teardown order (m_view before document) and staged rebind/reload paths
   compile and behave identically without a window.

## Acceptance predicate

Staged/reload sessions retain prior state and signal semantics with no own
window. NAMED CHECKS:
`deno task verify --filter sessioncheck --filter rollcheck` (controller-run at
gate B).

## Task-specific constraints

- No replacement per-song host, owned-window fallback, or compatibility alias
  (plan Global constraints; the task9 adapter is deleted by task22 in this same
  gate).
- Do not change document/history/lease/reload semantics — presentation-only
  change.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
