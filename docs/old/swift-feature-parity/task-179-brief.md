# Task 179 brief — menu focus is synchronous and survives dismissal arbitration

# Context

`shellwindow-label-commands` is a known red check (the sprint-3 gate note and
wave-171 gate both name it). Root cause is production, not the test:
`src/ui/songview/quick/drawer/AutomationMenu.qml:30-34` defers its focus grab
through `Qt.callLater` on `showing` — under full-lane load the menu takes focus
only after the test's `Down` key, so the key lands on the wrong surface.

A synchronous-focus fix (`enabled: visible` + `forceActiveFocus` on
`enabledChanged`) turns label-commands green but exposes the second half of the
bug: `swiftRollInput` steals focus back through `EditorSurface.qml:37`
(`onShowEventsChanged` unconditionally calls `rollInput.forceActiveFocus`) and
`EditorSurfaceMenus.qml:76/97` (menu-dismissal paths unconditionally return
focus to `rollInput`/`rulerInput`). That broke
`shell-grid-menu-automation::test_automationPointMenuRendersDeleteBeforeDismissal`,
which waits for the rendered point menu's `activeFocus`.

Surface: shell menu/dismissal focus arbitration — who owns keyboard focus while
an editor-surface menu is open, and where it lands when the menu closes.
Ledger spec: none — this is a bug fix with regression evidence, not a proof row.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-label-commands --verbose` and
`deno task verify:shell --filter shell-grid-menu-automation --verbose`.
Blocked rows: none.

# Exact write set

- `src/ui/songview/quick/drawer/AutomationMenu.qml` — remove the `Qt.callLater` focus grab; claim focus synchronously when the menu becomes showable.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — the `onShowEventsChanged` focus return fires only when the events surface actually held focus or the roll was the pre-toggle focus owner in the same pass (current-state arbitration, not remembered focus).
- `src/ui/songview/quick/swiftroll/EditorSurfaceMenus.qml` — the dismissal paths (`:76`, `:97` and the `onIsOpenChanged` handler) return focus to roll/ruler input only when the dismissing menu still holds active focus at that moment.
- `src/checks/editorqml/tst_ShellWindowLabelCommands.qml` — conditional only: if the fix changes observable timing the test's existing assertions should cover it; add a focus-ownership assertion only if none already proves the menu keeps focus through the `Down` key.
- `src/checks/editorqml/tst_ShellGridMenuAutomation.qml` — conditional only, same rule.

All five files are clean in `git status` at planning time (the performance wave
is committed; nothing is foreign).

# Prerequisites

None beyond the landed wave-175–178 gate at `0504b68b`. Read sprint-3 §22.

# Interface contract

A mounted editor-surface menu that becomes visible owns keyboard focus in the
same evaluation pass (no event-loop deferral). Focus returns to the roll or
ruler input only when the surface that is closing is the focus owner — a
focus-owner check at dismissal time, not a remembered owner (`menuHostHeldFocus`
/`menuDismissReturnsFocus` are the existing flags; this task replaces them with
current-state arbitration). There is exactly one place that routes focus back
to an input surface; menus do not spawn per-menu focus handlers.

# Implementation steps

1. Reproduce under load or by inspection: `AutomationMenu.qml` drops the
   `Qt.callLater` wrapper and claims `forceActiveFocus(Qt.PopupFocusReason)`
   synchronously on `showing`.
2. Gate the two focus-steal sites on the closing surface's live `activeFocus`:
   the menu gives up focus on dismissal only if it still has it; otherwise
   nothing moves. `EditorSurface.qml:37` fires only when the events page held
   focus or focus is orphaned by the toggle itself.
3. Keep one arbitration seam: whichever surface dismisses decides, in one
   place, whether the default input takes focus.
4. Run both lanes above. Both must be green in the same run; then run
   `deno task verify:shell --filter shell-grid-menu --verbose` to cover the
   sibling menu paths that share the dismissal code.

# Acceptance predicate

`shellwindow-label-commands` and `shell-grid-menu-automation` are both green,
with no deferred focus claim anywhere in the menu/dismissal path.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-label-commands --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-menu-automation --verbose
```

# Task-specific constraints

No `Qt.callLater` anywhere in the touched paths (there is also one at
`EditorSurface.qml` `onHintScopeCoveredChanged` — leave it unless it is part of
this bug). No remembered focus owner, no second dispatcher, no synthetic key
forwarding, no test-only API. If the synchronous claim needs `enabled`/`visible`
staging, keep it inside the menu item's own completion — not a timer, not
`callLater`.
