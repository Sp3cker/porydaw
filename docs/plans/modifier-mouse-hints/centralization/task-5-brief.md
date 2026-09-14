# Task 5 — Graph profile retention

## Context

PitchBendGraph is both target classifier and physical source, so it keeps one originating profile during its existing gesture. Centralize only its description rendering. Follow [spec.md](spec.md) and [Global constraints](plan.md#global-constraints).

## Exact write set

- `src/ui/pitchbendgraph.cpp`
- `src/ui/pitchbendgraph.hpp`

## Prerequisites

Task 1 IDs and task 2 typed publication contract; atomic acceptance with the other consumers.

## Interface contract

Rename the private `hintTextAt` selector to `hintProfileAt`, returning `ui::hint_profiles::Id`; it uses existing canvasRect/hitTest results for Empty/PitchBendVertex/PitchBendBackground. Replace `m_hintText` with `m_gestureProfile`, initialized Empty. Preserve existing helper entry points for publish/update/refresh/settle and their lifetime behavior; direct MouseHints calls use claim.

## Implementation steps

1. Replace the selector's returned strings with the fixed graph IDs; retain the current endpoint/interior/background classification and geometry.
2. Change the one retained originating value and call the renamed MouseHints::claim. Active-gesture updates reuse the captured ID without idle classification; only existing terminal inside settlement reclassifies, while outside settlement clears.
3. Delete m_vertexHint/m_backgroundHint and the local modifierLabel renderer, formatting-only includes/comments, and cached-string initialization. Preserve the guarded MouseHints borrow because this graph still publishes/clears directly.

## Acceptance predicate

Composed graph hover and a real gesture preserve current hints for interior/background/pinned endpoints, with no formatting per move and the originating ID retained until existing settlement. **Named checks, controller after atomic integration:** `deno task verify --filter pitch-bend --verbose`, `deno task verify --filter mainwindow-routing --verbose`, and graph/native popup smoke under [Verification](plan.md#verification).

## Task-specific constraints

No new hit tests, independent gesture mode, polling, or central graph inspector. Do not retain a cached QString alongside the ID or use catalogue absence to change graph action behavior.
