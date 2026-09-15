# Spec — drumset keyboard gutter labels

Agreed behavior, vocabulary, and forward-facing interfaces for
[plan.md](plan.md). Facts above the line are observed repository behavior;
contract sections are decisions this plan freezes.

## Vocabulary

- **Drumset voice** — a top-level voice whose `ToneData.type` has
  `VOICE_KEYSPLIT_ALL` set (UI label "Drumkit", `m4aVoiceTypeName`
  m4asemantics.cpp:134). Its `subGroup` points at a 128-entry `ToneData`
  array the engine indexes directly by key.
- **Sub-voicegroup** — any registered child `ToneData[128]` owned by
  `LoadedVoiceGroup.subGroups` (keysplit tables and drumsets alike).
- **Pad name** — a sub-voicegroup slot's display name, derived by the loader
  from the symbol on that slot's source line through the existing
  `set_voice_display_name` prefix strip (`DirectSoundWaveData_`,
  `ProgrammableWaveData_`, `voicegroup_`). Same rule as top-level
  `voiceNames`; empty string when the line carries no symbol (e.g. noise).
- **Initial program** — `MidiTimeline::tracks[t].firstProgram`, with `-1`
  (no program change) mapped to `0`, because `M4ATrack::currentProgram`
  starts at 0. This is what the track sounds like first; it is static.
- **Static drumset track** — the roll's primary track, classified once from
  its initial program's voice type. Per user decision a track keeps its
  classification for its entire lifetime; the VoiceChange lane and playback
  position are never consulted.
- **Gutter** — the piano-keyboard column of the Quick roll
  (`m_geometry.pianoKeyboardWidth`). **Hover chip** — the gutter's hover
  overlay (`TimelineQuickScene::hoverChip*`).

## Frozen interfaces

### poryaaaa (Task 1)

```c
/* LoadedVoiceGroup gains, parallel to subGroups (shared count/capacity): */
char (**subGroupVoiceNames)[VG_VOICE_NAME_LEN];

/* Borrowed per-slot display-name table of a registered sub-voicegroup.
 * Resolves the subgroup pointer to its names table once; callers index
 * slots directly for O(1) lookups. Returns NULL when vg or subgroup is
 * NULL, when the backing arrays are absent, or when subgroup is not a
 * registered member of vg->subGroups. Otherwise a non-NULL pointer to a
 * char[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN] table of NUL-terminated,
 * possibly empty strings. Valid until voicegroup_free(vg). */
const char (*voicegroup_subgroup_names(const LoadedVoiceGroup *vg,
                                       const ToneData *subgroup))[VG_VOICE_NAME_LEN];

/* Borrowed per-slot display name of a registered sub-voicegroup.
 * Returns NULL when vg or subgroup is NULL, when subgroup is not a
 * registered member of vg->subGroups, or when slot is outside
 * [0, VOICEGROUP_SIZE). Otherwise a non-NULL pointer to a NUL-terminated
 * string, possibly empty. Valid until voicegroup_free(vg). */
const char *voicegroup_subgroup_slot_name(const LoadedVoiceGroup *vg,
                                          const ToneData *subgroup, int slot);

- `subGroupVoiceNames[i]` is a `calloc`-zeroed
  `char[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]` allocated and registered
  together with `subGroups[i]`; indices stay aligned across capacity growth.
  `voicegroup_free` frees every table plus the pointer array.
  `voicegroup_subgroup_slot_name` validates the slot then delegates to
  `voicegroup_subgroup_names`.
- Generic: both `voice_keysplit` and `voice_keysplit_all` subgroups receive
  names. `ToneData`, `voicegroup_load` signatures, and every engine-facing
  `ToneData*` path are untouched. Ordinary `VOICE_KEYSPLIT` consumers can
  resolve `slot = keySplitTable[key]` and call the accessor later.

### Porydaw (Task 2)

```cpp
// src/ui/songview/detail.h (namespace songview::detail)
// Invariant-bearing row-label policy: construction is private, so only the
// (bank, timeline, track) factory can produce one — no caller can pair a
// drum classification with an unresolved bank/program.
class KeyboardRowSource {
  public:
    bool isDrum() const;
    QString drumPadName(int key) const; // trimmed name or empty
    QString rowLabel(int key) const;    // pad name, else keyName(key)
};
KeyboardRowSource keyboardRowSource(const LoadedVoiceGroup *bank,
                                    const MidiTimeline *timeline, int track);
```

- **Classification (exact rule):** with `bank`, `tl = timeline`, and
  `program = tl->tracks[track].firstProgram < 0 ? 0
  : tl->tracks[track].firstProgram`, the track shows drum pads iff `bank &&
  tl && program < VOICEGROUP_SIZE &&
  (bank->voices[program].type & VOICE_KEYSPLIT_ALL)`. Out-of-range track
  cannot occur (`primaryTrack` is 0-15). No bank or timeline → false.
- **Names table:** the factory resolves
  `voicegroup_subgroup_names(bank, bank->voices[program].subGroup)` once and
  stores it; `isDrum()` stays true even when that table is absent, so every
  row still renders as a pad with pitch-name labels. `drumPadName` returns
  the trimmed UTF-8 of `names[key]` when classified and named, empty
  otherwise (missing table, empty name, non-drumset, or key outside
  [0, VOICEGROUP_SIZE)) — an O(1) index, no per-row subgroup scan.
  `rowLabel` falls back to the existing `keyName(key)` ("C4") whenever the
  pad name is empty.
- **Invalidation:** `SongView::coordinateSelectionChange`'s `primaryChanged`
  branch adds `PianoRollQuickDirty::KeyboardText | HoverChip` to its existing
  roll dirty union. Bank and timeline replacement already request `All`
  (`setVoicegroup`, attach path) — no new wiring there.

### Rendering contract (Task 3 — scene level)

- `TimelineQuickView::synchronizeKeyboardText`:
  - Non-drumset track — behavior exactly as today: records only for visible
    rows that are white C keys (`!isBlackKey(key) && key % 12 == 0`), text
    `keyName(key)`, right-aligned into
    `keyboardWidth - pianoKeyboardLabelRightInset`.
  - Drumset track — one record for **every** viewport-intersecting visible
    row (black-key rows included: each row is a pad), full text
    `source.rowLabel(key)`, and a record width equal to the larger of the
    existing gutter budget or the measured text width plus the existing
    label inset. Pitch-name fallback keeps today's text for unnamed rows.
- `PianoRoll::keyboardHoverGeometry`: `name` becomes `source.rowLabel(key)`
  (full, un-elided). Chip width uses the cached pitch width
  (`m_keyboardHoverNameWidths[key]`) when `source.drumPadName(key)` is
  empty, else
  `QFontMetrics(m_keyboardHoverChipFont).horizontalAdvance(name)` plus the
  existing chip padding. The chip rect's left edge is clamped at
  `lyt::space(Space::Zero)`; wide chips therefore span past the gutter into
  the plot. Geometry fields, fonts, and `PianoRollGeometry::resolve` are
  unchanged. `TimelineQuickScene` publishes this full label and measured,
  clamped rectangle to the band-level QML chip.

### Label and chip overlay contract (Task 4 plus user follow-up — QML)

- The fixed-label container, `timelineQuickPianoHoverChip` background, and
  `timelineQuickPianoHoverChipText` are parented to `root.bandSide` (the
  roll band root exposed beside `gutterSide`/`plotSide`). The band root does
  not clip, and `gutterBox` starts at band-local x = 0, so their existing
  gutter-local coordinates need no mapping.
- Fixed drum labels use their measured record widths at `z: 3`; their full
  text can cross the keyboard boundary into the plot. Melodic record widths
  remain within the keyboard budget.
- Hover background `z: 8` and text `z: 9` remain above the fixed labels and
  plot content, below canvas-root chrome and popups.
- Keyboard key/highlight layers and `timelineRollGutterInput` remain inside
  the clipped `gutterBox`; the gutter keeps its fixed geometry and input
  ownership. None of the band-level text items accepts pointer input.

## Non-goals

- No note-face labels; no gutter width/font/geometry changes; no theme roles
  added (labels keep `song_view_piano_keyboard_label`).
- No program-change tracking, no per-tick reclassification, no timeline
  edits. No audio, engine, mixer, or `VoicegroupSource` parse changes.
- No new poryaaaa-side test target for the legacy loader (poryaaaa has no
  runtime that links it; see coverage map below).
- The dual width mechanism (cached pitch widths vs measured pad widths) is
  intentional: it keeps `pianoroll.{h,cpp}` out of the write set and leaves
  the pitch path byte-identical.
- The QML change uses the existing `bandSide` seam and reparents only the
  fixed-label container and two hover-chip items; keyboard drawing and
  input ownership stay in the gutter.

## Coverage map

| Behavior | Named check | Scenario |
| --- | --- | --- |
| Parsed subgroup names, lookup, warm reuse, and free (Task 1) | `vgloadcheck` | `verifyRichSubgroupNames` checks exact keysplit/drum names through one-shot, contextual, and warm `fixture_rich` loads |
| Slot-name resolution, fallback, and classification (Tasks 1-2) | `timelinepancheck` | isolated `DrumBankFixture` scenarios drive literal pad names and pitch fallbacks through `KeyboardRowSource` |
| Static lifetime classification across later program changes (Task 2) | `timelinepancheck` | `drumClassificationIgnoresProgramChanges` moves edit cursor and playhead across a later melodic program change |
| Full gutter labels, accidental-row contrast, measured overflow, hover geometry, and track-switch invalidation | `timelinepancheck` | direct text-model and scene assertions |
| Fixed labels and hover text cross the gutter into the plot; keyboard inputs stay clipped | `timelinepancheck` | `hoverChipOverlayUnclipped` checks realized Quick ownership and both text-content bounds |
| Cross-surface regression | `rollcheck`, `timelinepan-native` | controller sweep |

One minor limitation remains: `HoverChip` refresh while a real pointer remains
parked across a primary-track switch is not asserted. Synthetic `sendMouse`
does not own the real cursor, and Quick refresh emits `pointerLeave`, clearing
`m_hoverKey`. Hover content within one classification, track classification
changes, and the unclipped native realization are covered independently.

## Alternatives considered

- **Scout-proposed C helper `voicegroup_voice_label(vg, program, key)`**
  handling keysplit tables and top-level fallback inside poryaaaa: rejected —
  embeds Porydaw display policy (fallback, trimming, classification) in the C
  API and grows its surface; the slot-level accessor keeps poryaaaa owning
  only the parallel-array invariant.
- **Resolving names in SongView member functions**
  (`trackvoiceops.cpp`): rejected — an invariant-bearing
  `KeyboardRowSource` beside `keyName` resolves the bank subgroup-name table
  once from `(bank, timeline, track)`, keeps the SongView class untouched,
  and gives both consumers safe O(1) row lookup.
- **`rollcheck-static` as the coverage harness:** rejected because extending
  its externally declared QTest class expands the write set. `timelinepancheck`
  owns its test class locally and now uses canonical `PitchProjection`
  geometry plus isolated stack-owned `DrumBankFixture` storage rather than
  replicated camera algorithms or file-scope mutable arrays.
- **Timeline-dependent classification via `currentProgram`:** rejected by
  constraint (user accepts static classification; no program-change
  tracking).
- **Extending `vgloadcheck` with name-value assertions:** initially deferred
  for task sizing, then added during binding review. `verifyRichSubgroupNames`
  now checks exact parsed values and both accessors across cold, contextual,
  and warm real-loader paths.
- **Reparsing `.inc` in the UI or growing `VoicegroupSource`'s mirror:**
  rejected by constraint (no source reparsing).
- **Canvas-root chip overlay (`overlayRoot: root`, tooltip precedent):**
  rejected — requires band→canvas coordinate mapping for the chip rect; the
  band-root `bandSide` alias is transform-free because `gutterBox` sits at
  band-local x = 0, keeping the C++ rect bindings untouched.
