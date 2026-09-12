# Task R1 — Keymap catalogue collapse (K-B1, K-M5, K-M6, K-m7, K-m8)

## Route and seat

**SDD-track**. Reason: exported-symbol deletion across a public header changes the Registry's surface and both delivery recognizers read it. Seat: `qt-cpp-reviewer`.

## Context

The fixed-catalogue cutover is done; the Registry still wears configurable-registry clothes. Signed-off findings: **K-B1** dead descriptive plumbing (`Context`, `category`, `commands()`, `command()`, the `modifier` bool — zero external readers; `command()`'s one caller at editactions.cpp:77 uses only `info.name`); **K-M5** forwarding accessors (`bindings`/`modifierBinding` copy-or-forward cached statics; the tooltip/test single-stroke unpack copied three times at songview/detail.cpp:83, checks/eventviews/edits.cpp:85-88, checks/selectionkey/primitives.h:119-122); **K-M6** the `matches(QKeyEvent*)` overload plus `isModifierKey` visibility question; **K-m7** linear-scan `findDef` and the shippedBindings/bindings name split (opportunistic, as-is shape acceptable); **K-m8** the `Def` sentinel doublet. Qt signoff cleared K-B1 verbatim, K-M5 and K-M6 with the amendments below. Cost correction so implementers do not chase false copies: the per-call `QList<QKeySequence>` return is a shallow COW refcount bump, **not** a deep copy — the real wins are `const&` returns and the singleStroke helper.

## Exact write set

- `src/ui/keymap.h`
- `src/ui/keymap.cpp`
- `src/ui/songview/editactions.cpp` (sole `command()` caller) plus mechanically listed unpack/overload call sites (exception): `src/ui/songview/detail.cpp`, `src/checks/eventviews/edits.cpp`, `src/checks/selectionkey/primitives.h`, `src/ui/pitchbendeditor.cpp`, `src/ui/pitchbendgraph.cpp`, `src/checks/keyboard/tst_keymapcheck.h` (overload unpack)

Mechanical exception: more than three files because the deleted overload/example-unpack callers are exact, enumerable sites.

## Prerequisites

None — this is the first remediation task; R2 requires it.

## Interface contract

Registry public surface becomes: `sequences(id)` returning `const QList<QKeySequence>&`, `modifierBinding(id)`, `matchesModifier(mods, id)` with an explicit allowShift carve-out (see step 2), `matches(int key, Qt::KeyboardModifiers, id)` as the only match form, `isModifierKey` **remaining public** (production callers at pianoroll_commands.cpp:34,44 classify bare modifier keys for quick-update invalidation — a purpose `matches()` does not serve; the thermo report's demotion suggestion is corrected by the signoff), plus one `std::optional<QKeyCombination> singleStroke(id)` helper deleting the three unpack copies. `attach(id, action)` retained; its single-writer contract lands in [Task R2](task-R2-brief.md). Spec amendment: replace "Keep Context/category descriptive only and cache StandardKey alternatives/held modifiers once" in `spec.md#fixed-catalogue-and-action-ownership` with a single-struct statement (one table `{id, Qt::ShortcutContext, sequences, holdChord, name}` internal to keymap.cpp exposing only behaviour); replace `spec.md#source-evidence` line "`src/ui/keymap.{h,cpp}`: current defaults, mutable overrides, contexts, modifier bindings, attachment and conflict machinery" with "fixed catalogue, attach and match helpers". Delete listener-observable meaning of catalogue order with the `commands()` removal.

## Implementation steps ≤5

1. Delete `Context`, `category`, `commands()`, `command()`, the `modifier` bool, `Context`/`category` columns from all `kDefs` rows, and both `tr()` translation layers of `commands()/command()`; switch editactions.cpp:77 to `label(id)` (one local label accessor; names stay user-visible). Rewrite the four stale header comments to the immutable truth (K-m7/K-m9 wording pass for the touched comments only).
2. Route `detentUnlockHeld` (velocityarea.cpp:25-38) through `matchesModifier` **with** an explicit `allowShift` parameter (or a second catalogue id) so the existing Shift-ramp carve-out behavior is preserved — the unparameterized merge is rejected by signoff. Replace AutomationPage's `matchesPencilShortcut` read-back (automationpage.cpp:120-130) with `keys.matches(key, mods, "automation.pencil_mode")`, same values as what `attach()` installed, minus the action shortcut read-back. Its bespoke `key != 0`/`Key_unknown`/`isModifierKey`/mask guards are subsumed by `matches()`.
3. Add `singleStroke(id)`, take its three unpack copies as callers, switch `sequences(id)` to `const&`, and rename `shippedBindings`'s doubling role away (K-m7 naming pass — no file split; keep everything in keymap.cpp).
4. Delete the `matches(QKeyEvent*)` overload; unpack `event->key()/event->modifiers()` at the two event call sites and the check helper. Declare `isModifierKey` stays.
5. Fold [K-m8] the `Def` sentinel doublet only as far as construction folds allow (one resolved-sequences + `holdChord` representation); do not chase an index/hash optimization the signoff called optional.

## Acceptance predicate

Registry exposes only the behaviour-needed surface; all per-keystroke and gesture matching values are identical to today (transpose/held-modifier/SingleKeys values pinned by the existing checks); no caller of the deleted symbols remains anywhere in src/ or src/checks/. Selected checks: `deno task verify --filter keymapcheck --filter rollcheck-static --filter selectionkey --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not split keymap files (K-m7 stays per keep-files-small). Do not remove `isModifierKey`'s production use. Do not change `matches()` acceptance values, Shift carve-out semantics, or the E-B2 delivery-class filtering — that is the EditActions owner's territory; the E-M3 narrowed-bind-contract decision (option b) is recorded in task-R9-brief.md.
