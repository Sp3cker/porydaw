# Context

Cover both pitch-bend and modulation graph targets inside the existing shared Quick popup. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/pitchbendgraph.hpp`
- `src/ui/pitchbendgraph.cpp`

# Prerequisites

Tasks 5 and 17 (accepted popup/view integration)

# Interface contract

Add passive PitchBendGraph::hoverEnterEvent(QHoverEvent *), hoverMoveEvent(QHoverEvent *) and hoverLeaveEvent(QHoverEvent *) overrides, reusing hitTest/canvasRect/hasGesture. Preserve mouse, wheel, sampling, callbacks, rendering and undo semantics.

# Implementation steps

1. Enable hover and classify background, interior vertex, pinned endpoint and outside-canvas targets with the existing graph geometry/hit helpers.
2. Publish Shift or Alt line-drawing alternatives over background and Alt fine-time movement over interior vertices. Pinned endpoints have no modifier-specific alternative and publish an empty description; they must not advertise time movement.
3. Retain the originating profile during hasGesture; never call a mutating gesture path for hints. Use actual release/ungrab/cancel position: inside keeps/refreshes, outside clears, FocusLost alone is not hover loss. Hide/window detach always clears the physical item.
4. Reuse idle curve/geometry refresh and native scopeRefresh to recompute only a currently hovered idle graph. Respect service scope rejection; do not restore stale cached targets or scan the curve twice per movement. Captions, margins and pinned endpoints remain empty.

# Acceptance predicate

Real graph hover distinguishes background/interior/pinned targets while the existing drawing, vertex-edit and popup acceptance behavior is preserved. NAMED CHECKS: `deno task verify --filter rollcheck --filter host-integration --filter selectionkey-local-input --verbose` (controller), plus graph Native acceptance.

# Task-specific constraints

PitchBendGraph is a QQuickItem in the existing popup engine, not a QWidget or new window. No input grab or focus behavior may be added for hinting.
