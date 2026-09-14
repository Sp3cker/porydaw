# Context

Create the common service; native observation and status installation are Task 2, not this task. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/mousehints/mousehints.h`
- `src/ui/mousehints/mousehints.cpp`
- `CMakeLists.txt`

# Prerequisites

None

# Interface contract

Implement the complete public MouseHints contract in spec.md. install/setPointerDescription are declared here and defined by Task 2; they are nonvirtual and are not called before that consumer lands. For the private cross-file seam, forward-declare ui::WidgetHintsObserver and make it a friend; declare QPointer<WidgetHintsObserver> m_nativeAdapter so repeated MainWindow installations reuse one application observer; declare requestScopeRefresh() as the coalesced queued notification helper and one private constexpr nativeWindowBlockedProperty key shared by the observer and allowsSource. The adapter privately owns its current status-sink borrows and per-bar idempotence. Do not leave virtual methods undefined.

# Implementation steps

1. Create the QApplication-owned GUI-thread service and native modifier formatter; add only these new core sources to the existing CMake target.
2. Implement physical source/text replacement, source-checked clear and guarded currentSource/currentText. Disconnect old observations even for identical text; handle destruction after QPointer nulling without erasing a newer source.
3. Implement current Quick visibility/window/parent lifetime and application-state rejection. Implement allowsSource using actual native popup ownership and the observer-delivered QWindow blocked metadata; do not duplicate modality policy.
4. Declare scopeRefresh and hintChanged as Qt signals; implement requestScopeRefresh coalescing and application-activation recovery. Keep domain state and native family resolution out of this file.

# Acceptance predicate

The core compiles without unresolved virtuals and its source/scope invariants pass a temporary Qt consumer; Task 2 must complete the composed native acceptance before Milestone A is accepted. Controller: deno task build:checks; no claim of visible feature completion here.

# Task-specific constraints

Task 2 must not discover missing header interfaces privately. Review the private observer seam before it starts. CMake reuse is serialized and checkpointed per plan.md.
