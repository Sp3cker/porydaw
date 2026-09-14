# Context

Cover Quick numeric controls, automation parameter tabs and event rows/text editors through the shared context service. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/songview/quick/DragInput.qml`
- `src/ui/songview/quick/AutomationTabs.qml`
- `src/ui/songview/quick/EventListPage.qml`

# Prerequisites

Tasks 5 and 17 (accepted popup/view integration), Task 16 (HoverHint), Task 18 (reachable event-list hover)

# Interface contract

Use the HoverHint group protocol from spec.md, actual quickPopupSession ownership, and current root-context mouseHints. Keep selectRow, parameterPressed, DragInput scrubTo/WheelHandler, existing handler blocking, focus and key behavior unchanged.

# Implementation steps

1. Replace/reuse DragInput's existing input HoverHandler with one HoverHint group for Shift fine drag and Control wheel-by-ten. Bind gestureOwning to scrubDrag.active and releaseInside to the actual final centroid position mapped into the source. Preserve the deferred tap-select-all override: do not advertise ordinary Shift-click text selection. macOS Shift-axis compensation is not another action.
2. Use one publisher per parameter tab for Control ghost toggle, without canGhostParameter or activation/color changes.
3. Use one publisher per event cell: row alternatives outside editing; Shift-click text selection only while its child editor hover is active; editing margins empty. The child provides hover identity but never publishes independently.
4. Row headers show Control/Shift/Control+Shift row alternatives; toolbar, column headers/resizers and corner targets claim empty. Never publish from page/table ancestors. Bind existing cell drag ownership and actual release coordinates so release outside clears despite frozen hover.
5. Preserve existing input handlers. Shared scope refresh must restore a still-hovered group without hoveredChanged; any new imports follow the existing Quick module convention.

# Acceptance predicate

Shared numeric/tab/row/text hover displays the correct alternatives before modifiers are pressed, with unchanged edits, row selection and global shortcuts. NAMED CHECKS: `deno task verify --filter host-seams --filter eventviews --filter automation --filter selectionkey --verbose` (controller), plus the Quick-controls Native acceptance.

# Task-specific constraints

Combined Control+Shift is meaningful for event rows but not a substitute for the separate track-header precedence in Task 8.
