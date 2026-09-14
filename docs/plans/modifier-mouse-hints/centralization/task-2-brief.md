# Task 2 — Typed source claims

## Context

Task 1's catalogue replaces presentation strings at the MouseHints seam. Tasks 3–7 consume the renamed typed claim operation. Follow [spec.md](spec.md) and [Global constraints](plan.md#global-constraints).

## Exact write set

- `src/ui/mousehints/mousehints.h`
- `src/ui/mousehints/mousehints.cpp`

## Prerequisites

Task 1 interface. This task is accepted only with the other atomic consumers, not before they migrate.

## Interface contract

Public `Q_INVOKABLE claim(QObject*, ui::hint_profiles::Id)` replaces publish(QObject*, QString), including its name. The private non-invokable three-argument claim overload takes Qt::KeyboardModifiers and is available to the existing WidgetHintsObserver friend. Add a by-value `hint_profiles::Catalog m_profiles`. Declare static `setWidgetProfile(QWidget&, Id)` for task 3's definition. Remove publish, fragment, and setPointerDescription declarations and the fragment implementation. Keep currentText/hintChanged as text observations.

## Implementation steps

1. Install the catalogue value member and replace the publication/annotation declarations without adding compatibility overloads or extra public observation state.
2. Funnel typed publication through one source/scope-checked path. Resolve through the catalogue only after scope acceptance; transfer source observations before suppressing an unchanged-text signal. Empty remains an ownership claim.
3. Delete the native modifier formatter from this translation unit. Preserve clear/current-source lifetime, QPointer guards, singleton teardown, modality/application predicates, scopeRefresh coalescing, and signal signatures.
4. Rename allowsSource to allowsNativeInput, preserving its exact native/application/visibility implementation; update its internal claim call. Existing external call sites belong to tasks 3, 4 and 6. Do not add Quick session checks to this predicate.
5. Update only comments/includes made obsolete by these interface changes; preserve existing final `m_text` presentation state.

## Acceptance predicate

Integrated typed claims preserve source admission and transfer in the spec's single ordered contract, source-checked clear, and final caption text without a QString or old-name escape hatch. **Named checks, controller after atomic integration:** `deno task verify --filter mainwindow-routing --verbose` and the blank/same-profile composed smoke in [Verification](plan.md#verification).

## Task-specific constraints

No new currentProfile/currentClaim accessor, profile-history state, source registry, language observer, or QML singleton. The native metadata setter's definition belongs to task 3, not this task.
