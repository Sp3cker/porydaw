# Task R2 — attach() single-writer cutover (K-B2)

## Route and seat

**SDD-track**. Reason: deleting caller-side context writes across production wiring reads as trivial but one site is a live delivery-class contradiction, and the edit-routed double-fire hazard makes the remedy order-sensitive. Seat: `qt-cpp-reviewer`.

## Context

`attach()` (`keymap.cpp:321-330`) is `setShortcuts` + one `Qt::ShortcutContext` ternary, executed once per id. Five call sites pre-write the context before calling attach, so the write is order-dependent and "both agree only by coincidence" — except `automationpage.cpp:64-66`, which is worse (signed-off missed item): it pre-writes `Qt::WindowShortcut` for `automation.pencil_mode` while the catalogue gives it `Scope::EditorRouted`, and `attach()` then overwrites it with `Qt::WidgetShortcut`. Reordering those two lines today would silently flip the pencil action's delivery. Make `attach()` the sole shortcut-context writer and delete all five pre-writes. Load-bearing invariant the remedy must preserve: **EditorRouted→WidgetShortcut actions are parented to a plain QObject and never added to any widget, so the Qt shortcut system never delivers them — their entire delivery is manual** (ShortcutOverride filter, `handleEditKey`, `AutomationPage::eventFilter`). Window-scoped actions are QAction-delivered. Never "fix" the inertness of EditorRouted actions by associating them with widgets — keys then double-fire (QAction `triggered` plus manual dispatch reaching the same command).

## Exact write set

- `src/mainwindow.cpp` (delete pre-writes at the four attach sites, lines 250-252, 275-277, 294-296, 304-306)
- `src/ui/editordrawer/automationpage.cpp` (delete the contradictory pre-write at 64-66)
- `src/ui/keymap.cpp` (attach comment/contract tightening only — no behavioral change)

## Prerequisites

- [Task R1](task-R1-brief.md) — the catalogue this task's comment re-describes and the adjacency of edits to keymap.cpp.

## Interface contract

`Registry::attach(id, action)` remains the one writer of an action's sequences and shortcut context; callers pass only an action and never touch `setShortcutContext`/`setShortcuts` themselves. Spec amendment: replace the "`Registry::attach` configures QAction sequences and context once" sentence at `spec.md#fixed-catalogue-and-action-ownership` with "attach is the sole writer of an action's sequences and shortcut context; no caller pre-writes either. EditorRouted actions stay widget-association-free — manual delivery only; associating them with a widget double-fires their command." No spec change to the delivery table at `spec.md#physical-activation-and-local-priority`; this task implements its invariant, it does not alter it.

## Implementation steps ≤5

1. Delete the four MainWindow pre-writes verbatim (css copy action, solo, insert time, delete time) — attach already writes the identical value; assert via read-only inspection that no other `setShortcutContext` call near these sites belongs to non-keymap actions that must keep independent contexts.
2. Delete the automationpage.cpp:64-66 pre-write including its comment; the pencil action's context is now written once, by attach, as `Qt::WidgetShortcut`.
3. Tighten attach's comment to state the single-writer rule and the manual-delivery invariant from the spec sentence above.
4. Read-only sweep: `grep setShortcutContext` across src/ to confirm remaining hits are only (a) inside keymap.cpp's attach and (b) actions genuinely outside the keymap catalogue.

## Acceptance predicate

No caller pre-writes a catalogue action's shortcut context; the pencil action and the four Window actions deliver exactly the same keys through exactly the same single delivery path as before (no double delivery, no lost delivery). Selected checks: `deno task verify --filter mainwindow-routing-input --filter automation-editing --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not collapse `Scope`/`Qt::ShortcutContext` (that table choice is the EditActions owner's E-B1 work; this task only removes the duplicate writers). Do not touch `installWindowShortcuts`/`editorCommandForKey` filtering — the EditActions owner's E-B2 territory; the E-M3 option (b) narrowed-bind-contract decision is recorded in task-R9-brief.md.
