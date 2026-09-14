# Context

Keep uncertain consumer-visible lifecycle/input/layout regressions in existing suites; automation target coverage is Task 19. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`

# Prerequisites

All production tasks: 1–13 and 15–18 plus 20.

# Interface contract

Reuse MainWindowRoutingFixture and actual shown-window/Quick pointer delivery. Assert visible state/behavior across transitions, not helper forwarding, exact translated wording, private fields, counts or bare nonempty strings.

# Implementation steps

1. Move through actual plot/gutter, row/editor and existing same-profile controls using normal Qt delivery. Assert the displayed profile survives target changes; do not manually schedule old-source clears or destructors.
2. Exercise ordinary C++/QML drags released inside/outside, keyboard focus changes with a stationary pointer, switching/closing real tabs and popups, and application switching. Preserve original action outcomes; let production lifecycle paths cause hide/detach/destruction.
3. Open existing menu/form popups, move over covered targets, then dismiss normally without further pointer motion. Verify scope suppression and restoration to the actual target, including rename/editor and no-hint scrollbar/card regions. Native modality belongs to the actual WAV-export walkthrough, not a fabricated unrelated-window fixture.
4. Check status geometry/accessible full text while operational messages change, longest profiles elide, fonts change and the meter is visible/hidden, comparing equivalent layout states. Preserve existing message semantics.
5. Cover native modal suppression/recovery through the existing WAV-export progress workflow in the plan's native walkthrough. Reuse the controller's captured evidence; do not duplicate it with a new Qt-modality harness.

# Acceptance predicate

The composed behaviors above pass without weakening original action assertions, and actual native screenshots/walkthrough satisfy the plan table. Controller: deno task verify --filter mainwindow-routing --filter eventviews --filter trackheader --filter host-integration --filter selectionkey --verbose; final full suite remains the plan acceptance gate.

# Task-specific constraints

Do not add a new harness or permanent test of prose/metadata plumbing. The plan's realism rule excludes manufactured callback races and unsupported window arrangements; retain inexpensive production safety guards. Reuse private scratch fixtures and follow the single-baseline failure policy.
