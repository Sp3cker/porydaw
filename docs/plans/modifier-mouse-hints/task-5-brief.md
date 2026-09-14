# Context

Use the existing popup authority, not a new popup state machine. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/songview/quick/quickpopupsession.h`
- `src/ui/songview/quick/quickpopupsession.cpp`
- `src/ui/songview/quick/QuickPopupLayer.qml`

# Prerequisites

Tasks 4+15 and 16; dispatch with Task 17 as one disjoint integration wave.

# Interface contract

Mark existing owns(const QObject*) const Q_INVOKABLE without changing its logic/signature/callers. The existing isOpen property is the QML gate. Open claims empty using overlayRoot(), never the nonvisual session. Task 17 supplies root context and the physical-host mute/recovery consumer.

# Implementation steps

1. Expose owns through the meta-object without cloning its ancestry policy; the isolated QML signature probe confirmed const QObject* is invokable.
2. After canonical state, parenting and opening isOpenChanged, publish empty with the physical overlay root. Covered publishers must already be gated.
3. On end, clear the captured overlay root before detach/closing notification. Let popup children clear through real hide/window-detach; never restore an old owner snapshot.
4. Use HoverHint for appropriate existing underlay/form-shield no-hint groups. Do not put an empty publisher on an ancestor of different-profile popup content or change existing mouse/wheel/Space arbitration.

# Acceptance predicate

The composed 5+17 wave clears on popup open, rejects covered updates throughout, allows actual owned children, and restores stationary underlying Quick/native targets on close without changing popup actions/focus/shortcuts. Controller: deno task verify --filter host-integration --filter host-seams --filter selectionkey --verbose, plus popup Native acceptance; Task 14 covers regressions.

# Task-specific constraints

No static popupOwned flag, mirrored view popup property, ownership stack, enabled-action checks or assumption that the non-hovering underlay sends Leave.
