# Task 3 — Native complete-profile adapter

## Context

Replace native family text composition with complete profile selection. Task 7 supplies the two explicit widget annotations. Follow [spec.md](spec.md) and [Global constraints](plan.md#global-constraints).

## Exact write set

- `src/ui/mousehints/widgethints.cpp`

## Prerequisites

Task 1 enum and task 2's agreed claim/setWidgetProfile declarations. These interfaces are fixed before parallel dispatch; acceptance is atomic with their consumers.

## Interface contract

Define `MouseHints::setWidgetProfile(QWidget&, hint_profiles::Id)` with complete-profile metadata at `porydaw.mouseHintProfile`. The observer selects one ID and, only for NativeSpinBox/NativeSpinEditor/NativeFineSpinEditor, supplies the owning spin's style step modifier to the private claim overload. Missing annotation differs from explicit Empty. The status caption and its QString signal connection remain unchanged.

## Implementation steps

1. Replace pointerDescription/wheelDescription/resolveProfile string composition with one native profile selection path using the existing profileOwner/spinBoxFor/configuration facts. Honor the spec's native mapping and popup/header exclusions.
2. Replace custom pointer-text metadata with the typed complete-profile annotation and its event key. Keep widget identity and owner fallback behavior; do not append inherited wheel text after an explicit complete profile.
3. Delete per-widget key/text cache properties, configKey, invalidateProfile, and modifierLabel. Delegate rendering to the catalogue; retain style/metadata refresh events. Migrate native reconciliation's allowsSource calls to allowsNativeInput without changing their predicates or timing.
4. Preserve every grab, release, hover, popup/modal/application gate and queued reconciliation decision. Preserve HintCaption/install layout, font, theme, accessibility, and connection behavior exactly.

## Acceptance predicate

Native family hints retain their existing complete behavior, including overridden fine-control wheel alternatives and all three zero-style spin results, without per-widget rendered text or local wording. **Named checks, controller after atomic integration:** `deno task verify --filter mainwindow-routing --verbose` and the native style/control smoke in [Verification](plan.md#verification).

## Task-specific constraints

The annotation is complete, not a pointer-only override. Do not preserve a second implicit composition protocol, infer action eligibility, add a widget subclass deny-list, or modify status appearance.
