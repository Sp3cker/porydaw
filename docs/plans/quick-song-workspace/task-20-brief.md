# T20 — Prove production cross-toolkit focus and popup transitions

## Context

Gate B's production-input proof: the mainwindow-routing checks exercise the
actual shown MainWindow with real Quick tabs, real QuickPopupSession popups, and
cross-toolkit focus transitions. Consumes tasks 14 (strip controls), 15 (host
entry points), 16 (WorkspaceUi operations), 17 (window-free sessions), 18
(registry actions). Task23 later builds native-graphics coverage on this gate's
accepted behavior.

## Exact write set

- `src/checks/mainwindowrouting/mainwindowroutingfixture.h`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`

## Prerequisites

Interfaces from tasks 14–18.

## Interface contract

Produces check scenarios per spec S4/S5/S8; no production interface.
Requirements:

- Use the actual shown MainWindow and its real Quick tab controls — not
  `selectSongTab` calls — to prove buttons, shortcuts, and focus transitions.
- Cover: real custom popup/page close with immediate survivor editor input;
  A/B/A focus retention; readiness isolation (unready selected page blocks all
  page pointer/wheel/text/IME input while ready sibling stays editable);
  readiness loss cancels held audition/drag; late ready causes no focus steal;
  real QAction Space vs literal-text Space vs numeric-popup Space transport
  exception precedence; next/previous/F6/arrows/Enter through real
  control/action paths. Exercise both cyclic window-navigation boundaries,
  selection of a loading row, empty/single-tab inertness, and local arrow
  inertness at a missing neighbour (S4).
- Popup transitions per S5: pointer tab switch and popup-owner close with no
  outgoing forced focus; dismissal press → close owner → release is swallowed,
  next full click works; popup content destroyed before context/engine.
- Extend the shared fixture only for actual root/item discovery — never focus
  forcing; preserve existing QWidget text-control coverage.

## Implementation steps

1. Extend mainwindowroutingfixture.h with discovery helpers for the workspace
   root/strip/page items by objectName (`workspaceSongs`, `songTabStrip`,
   `songTab:<songKey>`, `songTabClose:<songKey>`); no focus-forcing or synthetic
   forwarding helpers.
2. In tst_mainwindowrouting_input.cpp: migrate/extend scenarios to drive real
   tab controls, registry QActions, and editor input; cover the focus/shortcut
   precedence and readiness-isolation cases above.
3. In tst_mainwindowrouting_lifecycle.cpp: cover popup owner
   close/switch/swallowed-release sequences, A/B/A retention, and late-ready
   no-steal through the shown window.
4. Remove assertions pinning per-song window destruction or QWidget identity
   rather than repinning them; keep all domain assertions.

## Acceptance predicate

Production shown-window input scenarios pass through real controls. NAMED
CHECKS: `deno task verify --filter mainwindow-routing --filter selectionkey`
(controller-run at gate B; the routing filter covers the input and lifecycle
files).

## Task-specific constraints

- Direct controller calls alone do not prove tab controls, drag/drop, shortcut
  precedence, or popup shielding (spec S8).
- No focus forcing, synthetic event fallback, or helper refocus in fixture or
  tests.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
