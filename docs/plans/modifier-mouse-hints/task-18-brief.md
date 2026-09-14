# Context

Own every previously omitted chrome path and the proven EventList hover-delivery obstruction. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/songview/quick/TimelineCanvas.qml`
- `src/ui/songview/quick/TimelineScrollbar.qml`
- `src/ui/songview/quick/DrawerChromeLayer.qml`

# Prerequisites

Tasks 5+17 and 16 accepted.

# Interface contract

Use existing geometry/physical items plus HoverHint; do not add a root-wide blocker or duplicate domain hit-testing. The event-list key-policy item remains the same focused object with the same interaction.

# Implementation steps

1. Restack timelineEventListInput below EventListPage at the same z. Preserve navigationInputActive and navigationFocusRequested wiring and update the misleading hover-transparency comment.
2. Put one empty HoverHint on the whole shared scrollbar footprint; preserve thumb colors, track clicks, wheel and keys. Tie retention/releaseInside to the existing thumb drag and actual mapped release coordinates.
3. Confirm the five existing drawer physical inputs claim empty through Task 4. Put one publisher on the inline value-prompt group: child text hover selects Shift-click selection; card/shield is empty. Never independently publish from its parent and child.
4. Preserve existing handler blocking/input acceptance. Do not attach a full-window DrawerChromeLayer publisher or introduce a new geometry authority.

# Acceptance predicate

Hover reaches real event cells and no-hint chrome replaces covered band hints without changing event-list press/wheel/reorder/focus or scrollbar/drawer actions. Controller: deno task verify --filter eventviews --filter scrollbar --filter editor-drawer --filter selectionkey --verbose, plus Quick-controls/header/popup native rows.

# Task-specific constraints

The restack changes previously broken hover reachability, not pointer action semantics; native parity is mandatory. Existing unrelated hard-coded geometry is not expanded by this task.
