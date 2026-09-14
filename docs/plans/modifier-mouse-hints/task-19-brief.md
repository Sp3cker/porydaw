# Context

Keep the uncertain current-target/tool regression separate from MainWindow lifecycle tests. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/checks/automation/hover/tst_automationhover.h`
- `src/checks/automation/hover/tst_automationhover.cpp`

# Prerequisites

Tasks 9 and 5+17 accepted; run after the full production wave.

# Interface contract

Reuse AutomationHoverTest and real Quick input. Compare observed profiles across target/tool transitions and fresh hover recovery, paired with existing editing/undo results; do not pin translated prose or add a hint-model test seam.

# Implementation steps

1. Cover node/phantom/sweep/pencil target differences. Switch the tool using the existing PencilToggle key command with the pointer stationary and no popup open, not a direct setter standing in for user input.
2. With the tool fixed, open an existing popup, move the pointer between real underlying automation targets, then dismiss through its normal keyboard action without further pointer movement. Recovery must match fresh hover at that target, not the pre-popup description; do not mutate background tool/document state behind the popup.
3. Keep existing live Alt snapping and press-captured Shift sweep behavior verified through actual edit/undo outcomes, not modifier-description presence alone.

# Acceptance predicate

The automation target/tool transitions and popup recovery pass with original edits/undo semantics preserved. Controller: deno task verify --filter automation-hover --filter automation-editing --filter editor-drawer --verbose, plus automation Native acceptance.

# Task-specific constraints

No registry/wording/forwarding assertions or new harness. Task 14 owns general lifecycle/layout cases, so do not duplicate them here.
