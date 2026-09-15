# Task 4 — SongTab URL Drop Delivery

## Context

Current song content may be a native widget or an embedded `QQuickWindow`. `SongTab::InputGate` already watches the container, Quick window, and root and is the canonical input seam. Extend that seam rather than adding QML drop logic or `MainWindow` forwarding. Task 5 consumes the signal. A focused existing onboarding slot proves the producer before it is checkpointed. Read [plan.md](plan.md) Global Constraints and [spec.md](spec.md) Accepted Drop.

## Exact write set

- `src/ui/songtab.h`
- `src/ui/songtab.cpp`
- `src/checks/onboardcheck/import.cpp`

## Prerequisites

None.

## Interface contract

- Add signal `void SongTab::urlsDropped(const QList<QUrl> &urls)`.
- A ready input gate accepts URL drag-enter and drag-move events reaching watched song content and emits the raw URL list exactly once on drop.
- Non-URL events and existing gated event types preserve their current handling.
- The interface reports raw URLs only; extension, count, locality, project, parse, and capacity policy stay in `WorkspaceUi`.

## Implementation steps

1. Add the signal and required Qt URL declaration/include without exposing `InputGate` internals.
2. Extend the existing gate's drag-enter/move/drop branches on all currently watched native/Quick objects; reuse its readiness/lifetime decisions.
3. Claim eligible URL drag phases consistently, emit once at drop, and preserve drag-leave/cancellation and non-URL behavior.
4. Extend `OnboardingTest::importWizard` to deliver URL drags to native/container and embedded Quick targets, observe exactly one `urlsDropped` emission per drop, prove non-URL input is ignored, and destroy the tab/root with no late emission.

## Acceptance predicate

`deno task build:app` and `deno task verify --filter onboardcheck --verbose` pass. `OnboardingTest::importWizard` observes raw URL delivery exactly once through both native/container and Quick routes, unchanged non-URL behavior, and safe teardown. Task 4 is accepted before Task 5 consumes the signal.

## Task-specific constraints

- No QML `DropArea`, synthetic forwarding, focus memory, or second dispatcher.
- Do not filter file extensions or local paths in `SongTab`.
- Do not claim tab-bar events.
