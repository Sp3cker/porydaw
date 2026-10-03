# Task 200 brief — mouse hints render the fork's modifier-fragment spacing and the unloaded edit actions stay bound

# Context

`src/swift/app/MouseHints.swift` renders profile fragments by concatenating
the modifier glyph directly onto the action — "⇧Right-drag",
"⌘Wheel" — where the fork's `hintprofiles.cpp::fragment` renders
`label + separator + ' ' + action` ("⇧ Right-drag", "⌘ Wheel"). The
state ledger recorded this at A250 as a noted wording residual under a
MATCHED row; the fork wording is the intended UI text (the fork comments
call the leading space deliberate house style), so this is a real wording
bug in a user-visible hint footer, not a representation difference.

The same wave's fresh-eyes pass found `state` A094–A099 — all six sites of
`editActionsStartUnboundWithNoWorkspace` — still GAP on the "no executing
check" note: the fork asserts the `m_editActions` QAction set exists and its
projected commands are disabled when a session opens with no saved
workspace. The mounted shell's no-tab state is observable through the
command/enablement surface (`tst_ShellWindowShortcuts.qml` already mounts
the unloaded window), so these rows adjudicate now: MATCHED where the
mounted shell's disabled command set is the observable law, RR where a
conjunct names QAction identity with no Swift counterpart.

Surface: the mounted shell hint footer and the no-tab shell's command
enablement.

Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
state.txt` A094–A099 (6 GAP), fork `tst_mainwindowrouting_state.cpp:271–276`
at reference `85b97239`; the A250 mapping note (fork `:728`) gains the
wording fix. No other ledger.

Verify lanes:
`deno task verify:shell --filter shellwindow-hints --verbose`,
`--filter shell-tabs-mouse-hints`, `--filter shell-drawer-parity-automation`
and `--filter shellwindow-shortcuts`.

Blocked rows left untouched: every other state row and ledger.

# Exact write set

- `src/swift/app/MouseHints.swift` — `profileText` fragments gain the space
  between the modifier label and the action, matching fork `fragment()`
  (modifier-only `"%1 or %2"` join, e.g. `page`, keeps its existing form).
  Every affected profile's expected string is spelled in the brief's
  contract: `⇧ Right-drag`, `⌘ Wheel`, `⇧ Wheel`, `⌘ or ⇧ Wheel`,
  `⇧ Drag`, `⌥ Drag`, `⌘ Drag`, `⇧ Click`, `⌘ Click`, `⇧⌘ Click`,
  `⌘ Right-drag`, `⌥ Right-drag`, `⇧ or ⌥ Drag`.
- `src/checks/editorqml/tst_ShellWindowHints.qml` — the two pinned literals
  (`:143`, `:172`) updated to the fork wording.
- `src/checks/editorqml/tst_ShellTabsMouseHints.qml` — the eight pinned
  literals updated to the fork wording.
- `src/checks/editorqml/tst_ShellDrawerParityAutomation.qml` — the five
  pinned literals updated to the fork wording.
- `src/checks/editorqml/tst_ShellWindowShortcuts.qml` — the mounted
  no-workspace enablement predicate for A094–A099: an unloaded shell
  publishes its command set with every projected edit command disabled.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` —
  A094–A099 closed (MATCHED or RR per clause); the two `Anchor: message`
  S-entries pinning `tst_ShellWindowHints.qml` literals refreshed to the new
  wording; the A250 mapping note re-worded from "noted wording residual" to
  record the fix.

# Prerequisites

All write-set files are clean at `432eaaa1`. Read sprint-3 §25 and the fork
`hintprofiles.cpp` `fragment`/`render`/`modifierLabel` at `fceecd88`
(`src/ui/mousehints/hintprofiles.cpp:14–260`) — confirm `QKeySequence
NativeText` on macOS yields "⇧"/"⌘"/"⌥" without a `+`, so
`fragment` emits `label + ' ' + action`. Check the fork
`editActionsStartUnboundWithNoWorkspace` body (`:271–276` at `85b97239`)
before choosing MATCHED vs RR per conjunct.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate. Expectations are independent literals, never read
back from `MouseHints`' own formatting. The wording change is a real UI text
fix — the check literals are fork literals, not copies of the new Swift
strings. `Shell*Support.qml` files stay untouched; if a predicate genuinely
needs one, message the controller first.

# Implementation steps

1. Fix `profileText` fragment join in `MouseHints.swift`.
2. Update the pinned literals in the three QML check files to the fork
   wording.
3. Add the mounted no-workspace enablement predicate to
   `tst_ShellWindowShortcuts.qml`; adjudicate A094–A099 per clause.
4. Close the six rows and refresh the two message anchors plus the A250 note
   in the state ledger, same commit.

# Acceptance predicate

The mounted hint footer renders "⇧ Right-drag: select time" (space after
the modifier glyph) and the unloaded shell's edit commands publish disabled;
executed predicates; `proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-hints --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-mouse-hints --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-drawer-parity-automation --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-shortcuts --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the state ledger and all four QML files. The wording
fix touches every profile, so `MouseHints.swift` edits are confined to the
fragment join — no other profile re-organization. Do not touch input or
native ledgers (204 owns them), `tst_ShellTabs.qml` (204), or any
`Shell*Support.qml`.
