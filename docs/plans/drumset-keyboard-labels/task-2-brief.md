# Task 2: Porydaw seam — resolve and publish subgroup names

> Historical pre-review dispatch record. Interface details below were
> superseded by the canonical final contract in `spec.md` and the landed
> invariant-bearing `KeyboardRowSource` implementation.

## Context

Task 1 gave `LoadedVoiceGroup` generic per-subgroup slot names and the
borrowed accessor `voicegroup_subgroup_slot_name(vg, subgroup, slot)`
([spec.md](spec.md#poryaaaa-task-1)); checkpoint CP1 has committed, pushed,
and staged the parent gitlink to that sha. This task resolves the contract
into roll-display helpers beside the existing `keyName` in
`songview::detail` and wires the one missing invalidation point so the
gutter repaints when the primary track changes.
The bank still flows through the unchanged lease seam
(`VoicegroupLease` → `SongTab::applyBankView` → `SongView::setVoicegroup`,
which already refreshes `PianoRollQuickDirty::All`). Producer for Task 3's
`detail::keyboardRowLabel` / `keyboardShowsDrumPads` contract.

## Exact write set

- `src/ui/songview/detail.h`
- `src/ui/songview/detail.cpp`
- `src/ui/songview.cpp`

## Prerequisites

Task 1 interface: `LoadedVoiceGroup.subGroupVoiceNames` and
`voicegroup_subgroup_slot_name`, available at the committed poryaaaa sha
(checkpoint CP1).

## Interface contract

```cpp
// detail.h, namespace songview::detail (SongView forward-declared):
bool keyboardShowsDrumPads(const SongView &sv);
QString keyboardDrumPadName(const SongView &sv, int key);
QString keyboardRowLabel(const SongView &sv, int key);
```

- Classification is exactly the frozen rule in
  [spec.md](spec.md#porydaw-task-2): primary track's initial program
  (`firstProgram`, `-1` → `0`) selects a voice with `VOICE_KEYSPLIT_ALL` in
  the loaded bank; no bank or timeline → `false`; never consults the
  VoiceChange lane or playback position.
- `keyboardDrumPadName` returns the trimmed pad name for `key` when
  classified and a name exists, `QString()` otherwise. `keyboardRowLabel`
  returns that name or falls back to the existing `keyName(key)`.
- `SongView::coordinateSelectionChange` (songview.cpp:977-987): the
  `primaryChanged` branch's `requestRoll` union gains
  `PianoRollQuickDirty::KeyboardText | PianoRollQuickDirty::HoverChip` (the
  scale-fold `All` path and all other branches unchanged).
- No `SongView` class declaration changes (helpers are free functions over
  the public `voicegroup()`, `timeline()`, `selectionModel()` accessors);
  `detail.cpp` adds includes for `ui/songview/songview.h`,
  `core/miditimeline.h`, and the `extern "C"` `voicegroup_loader.h` include
  pattern already used across porydaw.

## Implementation steps

1. `detail.h`: forward-declare `SongView`; declare the three functions with
   one-line contracts pointing at spec.md.
2. `detail.cpp`: implement them per the frozen rule; keys out of
   `[0, 128)` return empty/`keyName` fallback respectively.
3. `songview.cpp`: extend the `primaryChanged` requestRoll union with
   `KeyboardText | HoverChip`.

Edge cases: unused track (`firstProgram` `-1`) classifies through program 0
— matches what the engine sounds; a drumset-typed voice with `NULL`
`subGroup` yields empty pad names everywhere (callers fall back); banks
constructed by value in checks have `subGroupVoiceNames == NULL` — the
accessor's unknown-subgroup `NULL` path makes that identical.

## Acceptance predicate

Against CP1's staged gitlink, porydaw builds and the drumset fixture
load/warm-reuse/free corridors still pass (Task 1's ownership changes
exercised through real `voicegroup_load` on `fixture_rich`, whose slots 10/11
are `voice_keysplit_all`), with no UI regression from the invalidation line.
Named checks (controller runs them, from the Porydaw root, after Tasks 2-3
settle):

```sh
deno task verify --filter vgloadcheck --filter timelinepan --verbose
```

Coverage note: the helpers' value semantics are asserted by Task 3's
`timelinepancheck` scenarios (same verification surface — the split exists
only to respect the file cap; nothing narrows).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No
`src/project/voicegroupsource.*`, `src/audio/*`, or `src/core/*` edits; the
bank is read through the const borrow only. Do not add SongView members or
signals. No submodule edits: the gitlink pointer is owned by controller
checkpoint CP1, and the poryaaaa working tree stays untouched.
