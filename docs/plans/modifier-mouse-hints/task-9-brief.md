# Context

Cover all Drawer automation-canvas rows; parameter tabs are Task 12. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Task 17 (live view integration)

# Interface contract

AutomationCanvas::refreshHoverAt, setPencilMode and the existing NodeLaneHoverState supply target/tool identity. Preserve automationcanvas_gesture.cpp and nodelane gesture/value algorithms.

# Implementation steps

1. Publish distinct node, origin phantom, ordinary sweep-background and pencil-background profiles using the already resolved hover hit. Phantom has no time move; pencil has no Alt sampling claim.
2. Include Alt fine placement for the actual right-band/double-click paths and Shift-wheel only on the plot. Keep these operation labels separate from pencil stroke sampling.
3. Update setPencilMode through the existing primary plot host's non-claiming refreshMouseHint, using current idle hover classification. Do not store a raw gutter-host pointer or put hint text in numeric value-label caches. Scope recovery recomputes current idle target/tool instead of restoring old cached text.
4. Real input claims use the emitting host's setMouseHint; retain the originating profile during actual gestures. Bands never clear in leave/cancel/detach/hidden paths: Task 4 owns physical lifecycle.
5. Keep Shift sweep mode captured at press and existing live Alt/Control behavior unchanged; no lane eligibility, value-limit or document-content checks for hint visibility.

# Acceptance predicate

Node/phantom/sweep/pencil transitions expose the correct operation sets without changing edits or undo. Exercise the real stationary PencilToggle command separately from popup dismissal over a changed pointer target; do not change a background tool through a test-only setter while a popup owns input. NAMED CHECKS: `deno task verify --filter automation --filter editor-drawer --verbose` (controller); Task 19 supplies the focused regression.

# Task-specific constraints

No changes to nodelane algorithms, gesture variants, registry bindings or command enablement.
