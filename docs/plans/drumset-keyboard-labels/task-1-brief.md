# Task 1: poryaaaa subgroup slot-name ownership

> Historical pre-review dispatch record. Interface and verification details
> below were superseded by the canonical final contract in `spec.md` and the
> landed implementation, including the table-level O(1) lookup seam.

## Context

Porydaw's engine build (`plugin/porydaw/CMakeLists.txt` → `poryaaaa_engine`)
compiles the legacy loader at `plugin/voicegroup_loader.{c,h}`; this task
lives entirely in the poryaaaa repository. Today `parse_sub_voicegroup`
(voicegroup_loader.c:2238-2264) parses each sub-voicegroup's per-slot display
names into a stack temporary and discards them — only the `ToneData` array
survives registration. This task makes the registry own those names as
generic per-slot metadata so Task 2 can publish them and ordinary
`VOICE_KEYSPLIT` consumers can adopt them later. Producer for Task 2's
`voicegroup_subgroup_slot_name` contract ([spec.md](spec.md#poryaaaa-task-1)).

## Exact write set

- `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.h`
- `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.c`

## Prerequisites

None.

## Interface contract

- `LoadedVoiceGroup` gains `char (**subGroupVoiceNames)[VG_VOICE_NAME_LEN];`
  beside `subGroups` (header :62-65). It shares `subGroupCount` /
  `subGroupCapacity`: element `i` is the names table for `subGroups[i]`;
  `NULL` never appears while `subGroupCount > i` — both arrays grow and
  append together in `vg_register_subgroup`, transactionally: replacement
  pointer arrays for **both** are allocated first, existing entries copied,
  and the old arrays swapped/freed only after both allocations succeed, so
  `subGroupCount`/`subGroupCapacity` stay aligned and consistent on every
  failure path.
- `const char *voicegroup_subgroup_slot_name(const LoadedVoiceGroup *vg,
  const ToneData *subgroup, int slot)` — declared in the header's public
  section; returns `NULL` for NULL `vg`/`subgroup`, for a `subgroup` not
  registered in `vg->subGroups`, or `slot` outside `[0, VOICEGROUP_SIZE)`;
  otherwise a borrowed, NUL-terminated, possibly empty string valid until
  `voicegroup_free(vg)`. Lookup is a linear scan over `subGroupCount`
  (bounded by loaded sub-voicegroups; fine at this scale).
- Registration, parsing, and freeing behavior otherwise preserved:
  `vg_register_subgroup` still registers before parsing; on parse failure the
  registered subgroup remains owned and freed exactly as today (now with its
  names table). `voicegroup_load`, `voicegroup_load_samples`,
  `LoadedSampleSet`, `voicegroup_free` signatures unchanged.
- `ToneData` layout untouched; no engine or `m4a_*` file changes.

## Implementation steps

1. Header: add the `subGroupVoiceNames` field with a comment stating the
   parallel-array invariant and shared count/capacity; declare
   `voicegroup_subgroup_slot_name` with the contract above.
2. `vg_register_subgroup` (:664-679): accept the caller's names table
   (`char (*names)[VG_VOICE_NAME_LEN]`). When capacity is exhausted, perform
   the transactional growth frozen above — allocate both replacement pointer
   arrays up front, copy the existing entries into each, and only then free
   the old arrays and swap; if either allocation fails, return `false`
   leaving `subGroups`/`subGroupVoiceNames`/counts exactly as before
   (indices never skew). Append both pointers after the growth succeeds.
3. `load_sub_voicegroup_location` (:2266-2303): `calloc` the names table
   (`VOICEGROUP_SIZE * VG_VOICE_NAME_LEN`, zeroed) beside the subgroup
   `calloc`; free both on registration failure; register both; pass the
   registered table through `parse_sub_voicegroup` — replace its internal
   stack array with a `char (*names)[VG_VOICE_NAME_LEN]` parameter so
   `parse_voicegroup_file_session` and `continue_sub_voicegroup` write the
   registered storage directly (no copy).
4. `voicegroup_free` (:3763-3790): free each `subGroupVoiceNames[i]` in the
   subgroup loop, then the pointer array, keeping the existing NULL-guard
   style.
5. Implement `voicegroup_subgroup_slot_name` near `voicegroup_loaded_voices`
   (header contract verbatim).

Edge cases: keysplit subgroups (table-driven) take the same path — names are
generic, keyed by slot index, not by drumset semantics; the
`voicegroup_load_samples` keysplit path funnels through
`load_sub_voicegroup_session` → `load_sub_voicegroup_location`, so it needs
no separate handling; nested `.include` chains inside a sub-voicegroup
(`continue_sub_voicegroup`) keep writing the same registered table.

## Acceptance predicate

The changed loader compiles through porydaw's own build and the drumset
corridors still pass: after checkpoint CP1 commits/pushes the poryaaaa
change and stages the parent gitlink, `deno task build:checks` compile-proves
the new ownership in `poryaaaa_engine`, and `vgloadcheck` exercises
`fixture_rich` (slots 10/11 `voice_keysplit_all`) load / warm-reuse / free
through the new arrays. Behavioral value proof of the accessor is delivered
by Task 3's `timelinepancheck` scenarios; poryaaaa has no test runtime
linking this loader — that gap is named in
[spec.md](spec.md#coverage-map). Named checks (controller runs them, from
the Porydaw root, at CP1):

```sh
deno task build:checks
deno task verify --filter vgloadcheck --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not touch the
core-based loader under `plugin/voicegroup/`, `plugin/m4a*`, or
`plugin/hw_audio*`. Keep the diff minimal and C11; no direct
`cmake`/`ctest`/`xcrun` invocation — committing, pushing, gitlink staging,
and every build/check belong to controller checkpoint CP1
([plan.md](plan.md#checkpoints)).
