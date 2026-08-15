# Peel 04 — Automation node selection + group drag + group delete

> **STATUS: DONE 2026-08-12** — implemented on branch
> `peel/04-automation-node-selection` (`fe94597` feature + `e8fad4f` review
> fixes), full ASAN sweep + ctest green, awaiting user review/merge. Item 4's
> node delete turned out to be main's existing Lanes-scope `deleteTimeSelection`
> verbatim — documented in SPEC.md and pinned by probes instead of duplicated.

Read `docs/peels/GROUND-RULES.md` first. Target: main's `AutomationArea` inside
`src/ui/songview.cpp` (Pencil Mode already lives there — preserve it, including the
per-gesture `m_gesturePencil` latch). Source: branch `src/ui/editordrawer/`
`automationrows.cpp`, `automationgesture.cpp`, `automationpaint.cpp`; harness
`src/rollcheckautomation.cpp:1147-1292`. Batch move prefers Peel 01's
`moveLanePoints`; `applyRangeEdit` (already on main) is an acceptable substitute.

## The feature

Main's right-drag band already creates a lane-scoped time selection, but it does
nothing to points. This peel makes the selection mean something:

1. **Derived node selection.** A lane point is "selected" iff its row's identity is
   in the time selection's lanes and `startTick <= tick < endTick` (half-open) —
   branch `automationrows.cpp:247-254`. No stored set, no click-to-select.
2. **Selection rendering.** Selected nodes get a highlight ring
   (`palette().highlight()`); when ≥2 nodes are selected, nodes in unselected lanes
   dim toward `palette().mid()` (branch `automationpaint.cpp:603-643`; note the
   branch needed follow-up `876707c` — draw each node in exactly ONE of the
   selected/unselected passes). While the right-drag band is live, nodes under it
   already paint as selected (provisional highlight, `automationarea.cpp:133-150`).
3. **Group drag.** Pressing a node that is inside the selection drags ALL selected
   nodes (cross-lane) by one shared `dTick/dValue` from the grabbed node; `dTick`
   clamped so the earliest node can't go below tick 0; per-row value clamps; tempo
   floored at 1 (branch `automationgesture.cpp:102-127`). Live preview of every
   affected row's curve. Commit = ONE undo entry; the time selection shifts by
   `dTick` and republishes after the move (branch `automationarea.cpp:965-976`).
   Pressing a node outside the selection stays a single-point move (main's
   existing Gesture::Point).
4. **Delete/Backspace deletes the selected nodes** as one undo entry, leaving
   out-of-range points untouched (branch `automationarea.cpp:767-781`, harness
   :1266-1289). Wire into `AutomationArea::keyPressEvent` BEFORE the existing
   `handleEditKey` range-delete only when the deletion should be node-scoped —
   decide and document the precedence: main's `roll.delete` on a time selection
   currently deletes range CONTENTS across notes+lanes via handleEditKey. Simplest
   coherent rule: when the selection's scope is Lanes, Delete = the node delete;
   otherwise fall through. State the chosen rule in SPEC.md.

## Explicitly exclude (branch regressions — do NOT copy)

- The branch never calls `handleEditKey` from its automation keyPressEvent, losing
  copy/cut/nudge/transpose from the lanes. Keep main's dispatch.
- Branch band updates the published selection only on release; main publishes live
  during the sweep. Keep main's live publish (it's what the roll does too) unless
  it visibly conflicts with the provisional node highlight — if you change it,
  say so and why.
- Clipboard divergence (area-local automation clipboard) — different feature,
  and arguably a regression; skip.

## Tests

- New rollcheck section (rollcheck already drives the lanes; see the pencil-mode
  section for idioms): band-select two lanes' points → assert ring/dim via
  targeted pixel probes or state accessors; group-drag → one undo entry, shared
  delta, selection follows, undo restores bytes; outside-selection press still
  single-point; Delete/Backspace → one entry each, out-of-range survivors;
  half-open boundary (a node exactly at endTick is NOT selected).
- Adapt assertions from branch `rollcheckautomation.cpp:1147-1292`.
- Negative-test each probe; SF 1/1.5/2; full ASAN sweep + ctest; SPEC.md + CHANGELOG.
