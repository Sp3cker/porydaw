# Task 6 — QML profile transport and registration

## Context

Task 7 migrates all QML producers. This task changes their common transport and exposes task 1's enum using the existing registration seam. Follow [spec.md](spec.md) and [Global constraints](plan.md#global-constraints).

## Exact write set

- `src/ui/songview/quick/HoverHint.qml`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/quick/timelinequickview_window.cpp`

## Prerequisites

Task 1 metaobject/IDs and task 2 enum-typed public claim operation. Task 7's caller binding migration settles before any QML build/runtime acceptance.

## Interface contract

Register HintProfiles in Porydaw.Ui 1.0 using the spec's six-argument qmlRegisterUncreatableMetaObject call. Keep the existing context object. HoverHint imports Porydaw.Ui and exposes `property int profile: HintProfiles.Empty`; `_gestureProfile` is its existing originating-gesture state with an integer ID payload. Every former hints.publish call becomes hints.claim. There is no text property or compatibility binding.

## Implementation steps

1. Add enum registration inside the existing function-local static once block: once per process, not per engine. Separately preserve each view's existing context-property installation.
2. Replace text/_retained with profile/_gestureProfile and update the change handler and claim payloads. Keep current scope, gesture, release-containment, visibility, and source-clear decisions; do not reclassify a captured profile during the gesture.
3. Preserve `source` and the HoverHandler parent/physical-footprint contract. Keep service-availability guards; delete only the obsolete string initialization and text-specific comments.
4. In timelinequickview_window.cpp rename the existing allowsSource call to allowsNativeInput only. Do not change the queued recovery algorithm or assume that this native predicate checks Quick popup coverage.

## Acceptance predicate

Both the first and a second tab's composed QML scene load and publish enum-selected descriptions through the existing context object, with retained gesture/scope behavior unchanged and no producer string transport. **Named checks, controller after atomic integration:** `deno task build:app`, `deno task verify --filter mainwindow-routing --verbose`, and the two-tab QML smoke in [Verification](plan.md#verification).

## Task-specific constraints

Do not use qmlRegisterSingletonInstance for MouseHints, expose native style modifiers to QML, invent string keys/JavaScript profile lookup, or replace enum-typed C++ publication with an int/QString fallback to suppress a registration failure.
