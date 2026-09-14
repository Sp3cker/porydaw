# Task 1 — Central profile catalogue

## Context

Extract hint presentation into the catalogue described in [spec.md](spec.md), under [Global constraints](plan.md#global-constraints). Tasks 2–7 consume its enum; task 2 owns its application-lifetime instance. This produces an interface for an atomic refactor, not an independently shipped feature.

## Exact write set

- New `src/ui/mousehints/hintprofiles.h`
- New `src/ui/mousehints/hintprofiles.cpp`
- Existing `CMakeLists.txt`

## Prerequisites

The plan's entry gate and accepted architecture contract. Read current wording producers from the spec inventory before extracting; they are read-only in this task.

## Interface contract

Produce `ui::hint_profiles::Id` with Q_NAMESPACE/Q_ENUM_NS and the exact spec inventory, Empty=0. Produce non-QObject `Catalog::text(Id, Qt::KeyboardModifiers = Qt::NoModifier) -> QString`. Implement complete cached descriptions under the spec's cache, translation, modifier, and zero-style rules. Do not register a QObject instance or inspect a source widget.

## Implementation steps

1. Declare the namespace enum and catalogue; keep rendering helpers/cache representation private.
2. Extract existing literal wording and full-profile order into the catalogue. Keep the canonical keymap reads and velocity chord-collision branch; preserve equivalent-modifier templates without turning them into combined chords.
3. Cache by profile and applicable native spin modifier, including valid empty results, for the owner's lifetime. Avoid formatting/deep copies on hits; no construction-time translation or new observers.
4. Add both new files beside the mousehints sources in CMake so AUTOMOC processes the namespace metaobject. Preserve QML module configuration and all existing targets.

## Acceptance predicate

Every inventoried current description is representable without caller text; the enum metaobject and catalogue compile and render unchanged descriptions when exercised through the integrated publisher, including native zero-modifier variants. **Named checks, controller after atomic integration:** `deno task build:app`, `deno task verify --filter mainwindow-routing --verbose`, and the native style/composed smoke in [Verification](plan.md#verification).

## Task-specific constraints

Do not remove text from its current producers here; task 7 owns those files. No public fragment/entry/command builder, no string-key table, no process-global QObject or tab-owned cache. Do not add a test merely enumerating IDs or pinning every phrase.
