# Task R3 — keymapregistry immutability regression (K-B3)

## Route and seat

**SDD-track**. Reason: the change replaces vacuous test setup with a real regression contract; an SDD reviewer verifies the seeded overrides are actually exercised. Seat: `qt-cpp-reviewer`.

## Context

`src/checks/keyboard/keymapregistry.cpp:15-18` seeds four `keymap/*` QSettings keys (`roll.transpose_up` = `Ctrl+Alt+U`, `transport.play_pause` = empty, `roll.velocity_drag` = `Shift`, `velocity.detent_unlock` = empty). Post-slice, `keymap.cpp` includes no QSettings and reads none of these; the assertions at :35-68 and :87-91 pass identically with or without the setup, and the play_pause/Space assertion at :59-60 is vacuous — the test claims override-immunity and proves nothing. The QSettings isolation plumbing in `tst_keymapcheck.h:26` (`m_settingsDirectory`) exists only to serve these dead writes (the settings-dialog check has its own isolation). Signed-off remedy: turn the dead seeding into an explicit immutability regression — keep the seeds, assert the Registry still reports shipped bindings and rejects the override chords.

## Exact write set

- `src/checks/keyboard/keymapregistry.cpp`
- `src/checks/keyboard/tst_keymapcheck.h`

## Prerequisites
- [Task R1](task-R1-brief.md) for surface naming only — sequence R3 after R1 lands (its `bindings(id)`/`matches` contract is preserved by R1's change); R3 is otherwise independent of R1's deletions.

## Interface contract

The immutability contract becomes test-visible: seeding a `keymap/<id>` settings key must not change what `Registry::bindings(id)`/`matches(...)` report; a seeded override chord (`Ctrl+Alt+U` against `roll.transpose_up`, empty against `transport.play_pause`) is rejected while the shipped sequence still matches. Spec-amendment lines: none in spec.md — its line 22 ("Bindings are fixed platform-aware defaults; Old `keymap/` settings do not affect behavior") is already correct and this task is its first actual test proof, recorded as a progress.md note instead. Delete the `m_settingsDirectory`/`QSettings::setPath` isolation only if nothing else in this harness needs it. The assertion forms used here (`bindings(id)`) are preserved by Task R1's surface change.

## Implementation steps ≤5

1. Keep the four `setValue` seeds; move them to the dedicated immutability test function with a comment naming spec.md line 22.
2. Write `QCOMPARE(registry.bindings("roll.transpose_up"), shipped)` before asserting `!matches(Ctrl+Alt+U, …)` and `matches(Key_Up, NoModifier, "roll.transpose_up")`.
3. Assert Space still matches `transport.play_pause` with the empty-string seed present (this is the previously vacuous assertion; make it meaningful by first `QCOMPARE(bindings("transport.play_pause"), shipped)`).
4. Assert `matchesModifier(ShiftModifier, "roll.velocity_drag")` and `matchesModifier(ControlModifier, "velocity.detent_unlock")` unchanged by the `Shift`/empty seeds.
5. Remove the `m_settingsDirectory` member and QSettings path redirects from tst_keymapcheck.h:26 if the read shows no other use; keep a minimal named-comment pointing at the seeded store.

## Acceptance predicate

The check fails if the Registry ever reads `keymap/*` settings (the seeded override is actually exercised, not skipped); all existing shipped-binding and modifier-chord assertions pass. Selected checks: `deno task verify --filter keymapcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not weaken the real settings isolation used by separate checks in this harness; do not add a QSettings round-trip reader in keymap.cpp under the guise of test verification.
