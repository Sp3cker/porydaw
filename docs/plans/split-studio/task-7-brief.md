# Task 7 — PorydawKitStudio: module + kit draft domain + audition tone (AppAudio)

## Context

Seventh task of the Split Studio plan; the domain core of the new studio.
Consumers: task 8's source session and task 9's presenter publish the
draft's zone rows, build saves from `KitDraftCodec`, and play keys via
`KitAuditionTone`; task 10's workflow plays draft keys through
`AudioAudition.publishKitTone`. Producers consumed: task 1 (`SampleSlice`
for fixtures; `SampleRatePolicy`), task 2 (`kitBlankChildLine`, public, R3),
task 5 (module dependency only — `PcmAuditionPlayer` is consumed by tasks
8–9, not here). Engine facts the codec encodes: keysplit-all children play
their own fixed `key` and rhythm pan from child `panSweep & 0x80`
(`m4a_track.c:413-422`); keysplit pitches from the incoming key; `WaveData`
has no start offset (each slice its own asset). The module rule requires an
edit-floor measurement, controller-run and recorded in `docs/BUILDING.md`.

## Exact write set

- Create `src/swift/kitstudio/CMakeLists.txt`
- Create `src/swift/kitstudio/KitZone.swift` (zone value + `KitMode`)
- Create `src/swift/kitstudio/KitDraft.swift` (snapshot, both mode views,
  the only mutation paths, undo stack)
- Create `src/swift/kitstudio/KitDraftCodec.swift` (zones ⇄ sub-voices/table,
  audition-tone building)
- Create `src/swift/app/audio/KitAuditionTone.swift` (value description —
    PorydawAppAudio owns it, R1)
- Edit `src/swift/app/audio/AudioSampleAudition.swift` (kit publication
  slot storage + publish variant)
- Edit `src/swift/app/audio/AudioAudition.swift` (`publishKitTone`
  forwarding into `AudioSampleAudition`, exactly how `publishSample`
  flows; `SampleAuditionOutput` and `NativeAudio` are unchanged)
- Edit `src/checks/audio/AudioAuditionChecks.swift` (kit publication rows)
- Create `src/checks/kitstudio/KitDraftChecks.swift` (new suite
  `runKitDraftSuite`)

Controller-owned: module CMake enrollment (root list), `PdcSuite` enum +
dispatch case + `checkcatalog.cpp` lane `kitstudio-draft`, `-enable-testing`
leaf, `docs/BUILDING.md` rows.

## Prerequisites

Tasks 1, 2, 5 (interfaces only): `SampleSlice`/`ProcessedSample`,
`kitBlankChildLine`, and the compiled `PorydawSampleUI` dependency edge.
The draft itself is pure state over existing `PorydawVoicegroup` values.

## Interface contract

`spec.md → PorydawKitStudio (task 7)` and `→ PorydawAppAudio (task 7's
audio addition)` — exact signatures for `KitZone`, `KitMode`, `KitDraft`
(+`Snapshot`), `KitDraftCodec`, `KitAuditionPsg`, `KitAuditionTone`
(+ nested `Child`, `KitAuditionMode`), and
`AudioAudition.publishKitTone(_:key:)`. Pinned
behavior:

- **Module deps** (R2): `PorydawSample` (`SampleSlice`, `ProcessedSample`),
  `PorydawSampleUI` (compiled dep; types consumed from task 8 on),
  `PorydawVoicegroup` (`VgVoice`, `KeysplitTable`, `kitBlankChildLine`),
  `PorydawAppAudio` (`KitAuditionTone` — downward edge per R1),
  `QtBridge`. No `PorydawDocument`, no `PorydawAppPresentation`, no
  `PorydawCore`.
- `KitDraft` invariants: zones within one view are sorted, disjoint
  (`start <= end`, next `start > previous end`), keys in 0…127;
  `setDrumkitZones`/`setKeysplitZones` are the ONLY mutation paths and
  each pushes one undo entry snapshotting BOTH views; input violating the
  invariants is rejected (returns false, state unchanged — never silently
  clamped, R10); `load(_:)` replaces state and clears undo (dirty false);
  `markClean()` sets dirty false keeping undo; `dirty` is true after any
  accepted mutation or undo/redo diverging from the last clean snapshot.
  Pure Swift: no bridged members, no revision counters (the presenter owns
  observation).
- `KitDraftCodec.drumkitZones(children:)`: runs of adjacent sub-slots with
  the same sample symbol and identical params collapse into one zone;
  child key equal across the run ⇒ Pitched off; rising by exactly +1 per
  slot ⇒ Pitched on; any other key progression splits the run. Sub-slots
  whose line equals `kitBlankChildLine` are unassigned. Non-sample macros
  become locked zones (one per maximal run of the identical voice).
- `KitDraftCodec.keysplitZones(children:table:)`: runs of equal consecutive
  `table` values form zones `[runStart, runEnd]`; a run whose table value
  has no defined child slot (nil child or index ≥ children.count) yields
  unassigned keys (no zone); zones clamp at the sub-group's highest defined
  slot.
- `children(from:mode:)`: Drumkit — exactly 128 children, sub-slot == MIDI
  key; Pitched off ⇒ child key = zone root for every key in range, Pitched
  on ⇒ root + per-key offset; pan written only in drumkit mode (encoded to
  the engine's `panSweep` rhythm-pan byte: pan −64…63 ⇒ 0xC0 + pan/2 per
  `m4a_track.c:420-421`); unassigned keys ⇒ nil; locked zones emit their
  preserved `lockedVoice` (round-trip: locked zones are carried, never
  dropped). Keysplit — children indexed by zone ordinal (zones sorted by
  `startKey`; locked zones occupy their own ordinal with their preserved
  voice).
- `table(from:name:)`: **full-range** table — `startingNote = 0`,
  `maxNote = 128`, every key 0…127 mapped to its zone's ordinal; a key
  inside no zone maps to the ordinal of the last zone starting before it
  (0 when none). Split Studio tables are never truncated above the last
  zone, so gaps at the top survive the round-trip (R14; task 2's writer
  emits runs through 127 for `maxNote == 128`).
- `auditionTone(draft:key:)`: builds `KitAuditionTone` for the clicked key
  from the active mode view — Drumkit: keysplit-all wrapper semantics with
  the child key/panSweep per zone; Keysplit: keysplit wrapper + table;
  locked zones map their preserved `VgVoice` to a `.psg(KitAuditionPsg)`
  child (field copy in this module — AppAudio never imports
  PorydawVoicegroup, F3); sample
  children reference the rendered slice PCM (caller supplies already
  rendered buffers — the function is pure over its inputs).
- `publishKitTone`: allocates the sub-group array, child waves and table
  inside `AudioSampleAudition`-owned slot storage; the wrapper tone is what
  `apply` installs as `tracks.1.currentVoice`; retirement follows the
  existing generation/acknowledgement protocol
  (`AudioSampleAudition.swift` publish/apply/retiredSlot). One kit
  publication consumes one of the four slots like any sample.

## Implementation steps

1. Write the module CMake file per the dep list (same shape as task 5's).
2. Write `KitZone`/`KitMode`, then `KitDraft` per the contract (plain
   `final class`, value snapshots, no I/O).
3. Write `KitDraftCodec` as pure static functions (no I/O) so checks call
   them directly. Range legality: the codec is total over well-formed
   zones; out-of-range voice fields are a caller bug — clamp at the
   presenter/workflow boundary, never here.
4. Write `KitAuditionTone.swift` in `src/swift/app/audio/` (nested
   `KitAuditionMode` and `KitAuditionPsg` so AppAudio imports neither the
   higher module nor PorydawVoicegroup, F3), then
   extend `AudioSampleAudition` + `AudioAudition` per the contract. No new
   synchronization; follow the existing publish/adopt/retire protocol.
5. Append `AudioAuditionChecks` rows (`swiftcore/KitAudition::`):
   publication returns true with a free slot, false when all four are
   live; `off()` clears; the installed `currentVoice` carries the wrapper
   type bits and its sub-group resolves the expected child storage for a
   key (assert pointer identity with the slot's child storage); retirement
   reclaims after note-off (existing protocol row shape).
6. Write `KitDraftChecks.swift` (`runKitDraftSuite`, labels
   `swiftcore/KitDraft::`): codec round-trips (zones → children/table →
   zones) for drumkit pitched/unpitched/pan/blank, keysplit runs with gaps
   and locked zones, top-of-range gaps surviving the full-range table;
   collapse rules (equal params merge, +1-rising merge, broken run splits);
   draft invariants (rejects unsorted/overlapping/out-of-range input
   without state change); `load`/`markClean`/`undo`/`redo` restore both
   views; dirty lifecycle; `auditionTone` field-level correctness for
   pitched/unpitched/pan and locked zones. Keep the suite ≤ 0.45 s
   (plan.md budget).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter kitstudio-draft`
  — new lane running `runKitDraftSuite`. Covers: zone invariants and
  rejection behavior, codec round-trips incl. locked zones/gaps/full-range
  tables, draft undo/dirty lifecycle, audition-tone building.
- `uv run --no-sync dev checks --filter swiftcore-playback-audition`
  — `runAudioAuditionChecks` with the kit publication rows. Covers: slot
  ownership, wrapper installation, retirement under the existing protocol.
- `uv run --no-sync dev checks --filter swiftcore-playback`
  — regression: the playback engine lanes are untouched by the audio-slot
  extension.

Runtime prerequisites: none; offscreen. Added rows are budgeted at 0.50 s
(lane 0.45 + audition 0.05; plan.md budget table).

## Task-specific constraints

- No bridged declarations in this task (the presenter is task 9) — the
  draft types are plain Swift; `KitZone` is a struct, the codec an enum of
  pure functions.
- `AudioSampleAudition` changes are additive: existing `publish` call sites
  and the four-slot budget are untouched.
- Per plan Open blockers: if the worktree has rebased onto `fork-main` and
  `src/swift/playback/audition/AudioAuditionVoices.swift` exists, read it
  first and reuse its accepted-audition allocation policy for the kit
  publication instead of adding a parallel one; report the divergence.
- No QML, no presenter, no session types here. Task 9 must not edit
  `KitDraft.swift` (R10) — if it needs a draft API, that API belongs here.

## Controller verification

1. Enroll the module (root CMake include + `PorydawApp` link — deps per the
   contract), add the `PdcSuite` case + `checkcatalog.cpp` lane
   `kitstudio-draft` (`--swiftcore` handler, suite `kitDraft`,
   decomp-project fixtures like `projectstore-keysplits`), add the check
   source to `src/checks/CMakeLists.txt`, and the kitstudio + audio source
   lines.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter kitstudio-draft`
3. `uv run --no-sync dev checks --filter swiftcore-playback-audition`
4. `uv run --no-sync dev checks --filter swiftcore-playback`
5. Edit-floor measurement: touch `src/swift/kitstudio/KitDraft.swift`,
   warm `build:app`, record before/after in `docs/BUILDING.md`.
6. `uv run --no-sync dev format --check` on changed lines.
