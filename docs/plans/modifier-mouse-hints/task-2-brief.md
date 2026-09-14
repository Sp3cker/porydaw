# Context

Install the native adapter and visible middle status region while preserving operational messages. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/mousehints/widgethints.cpp`
- `CMakeLists.txt`
- `src/mainwindow.cpp`

# Prerequisites

Task 1 accepted; its CMake edit is the first reuse boundary.

# Interface contract

Define MouseHints::install/setPointerDescription and private ui::WidgetHintsObserver in widgethints.cpp using Task 1's private seam. MainWindow::buildUi installs the region before the existing permanent meter. No second service or status-tip transport.

# Implementation steps

1. Implement the private eliding caption widget and proven reservation 1 / hint 2 / meter 0 layout, preserving the complete current accessible description but no tooltip-inspection handoff.
2. Implement one observe-only native family adapter from the inventory, custom pointer metadata and inherited wheel composition. Cache stable profiles; do not enable global mouse tracking or publish propagated ancestor mouse copies.
3. Track the actual pressed native source, not only explicit mouseGrabber. Settle real release/ungrab/visibility; focus loss alone does not clear. Use discrete native hit recovery, not per-pixel tree searches.
4. Mirror Qt WindowBlocked/Unblocked events on their QWindows; reconcile native popup Show after registration through a queued callback, Hide after deregistration. Clear disallowed current owners and request shared scope recovery without changing event acceptance.
5. Register widgethints.cpp and call install in buildUi. Preserve every operational message, polyphony, existing typography/theme and ownership path.

# Acceptance predicate

In the actual MainWindow, ordinary and custom native targets coexist with operational text and meter through hover, native dialog/popup, implicit drag release and font/width changes. Controller: deno task verify --filter mainwindow-routing --filter transportcheck --verbose, plus Native acceptance families/layout/lifecycle; Task 14 later retains the uncertain regression cases.

# Task-specific constraints

No MainWindow signal relay, bar subclass, manual region geometry, tooltip history or action eligibility. Review cohesion if the private native file exceeds 600 lines.
