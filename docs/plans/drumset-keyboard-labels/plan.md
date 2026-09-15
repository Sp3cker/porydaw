# Drumset keyboard gutter labels

Quick piano-keyboard gutter labels and hover text name drum pads for a track
whose voice is statically a drumset (`VOICE_KEYSPLIT_ALL`), with pitch-name
fallback and fixed gutter geometry. The names come from poryaaaa's loaded
bank as generic per-subgroup slot metadata — no source reparsing, no audio or
engine changes, no timeline-dependent program tracking.

## Current-state findings (observed)

- Porydaw's engine build compiles the **legacy loader** at
  `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.{c,h}` via
  `plugin/porydaw/CMakeLists.txt` (`poryaaaa_engine`; include dir
  `packages/poryaaaa/plugin`). The `plugin/voicegroup/` core-based loader is
  poryaaaa-CLAP-only; porydaw never links it. The submodule is clean at
  poryaaaa main `27e68ec10859d73576b078ca7a7b1bc24126f34b`, which is also
  the Porydaw gitlink at HEAD (`git ls-tree HEAD external/poryaaaa`).
- `LoadedVoiceGroup` (voicegroup_loader.h:41-71) owns `voices[128]`,
  `voiceNames[128][48]`, and the subgroup registry
  `ToneData **subGroups` + `subGroupCount/subGroupCapacity`.
  `parse_sub_voicegroup` (voicegroup_loader.c:2238-2264) already parses each
  sub-voicegroup's per-slot names into a **stack temporary and discards
  them**; only the `ToneData` array survives via `vg_register_subgroup`
  (:664-679, single registration call site :2284). `voicegroup_free`
  (:3763-3790) frees the subgroups.
- The bank reaches the UI through the existing seam:
  `VoicegroupLease`/`LoadedBankView` (src/project/voicegroupsource.h:38-95,
  :448-452) → `SongTab::applyBankView` (songtab.cpp:199-201) →
  `SongView::setVoicegroup` (songview.cpp:930-940, refreshes
  `PianoRollQuickDirty::All`). Banks are published immutable
  (`const LoadedVoiceGroup *`).
- Gutter rendering: `TimelineQuickView::synchronizeKeyboardText`
  (timelinequickview_pianoroll.cpp:572-598) emits `PianoMidiLabel` records
  for visible white C rows only, text `detail::keyName(key)`. Hover:
  `PianoRoll::keyboardHoverGeometry` (pianoroll_geometry.cpp:167-185) sizes
  the chip from `m_keyboardHoverNameWidths` (precomputed pitch-name widths,
  pianoroll.cpp:48-50); `synchronizeHoverChip` (:600-611) forwards to
  `TimelineQuickScene::setHoverChip`. Both QML delegates clip
  (`PianoRollCanvas.qml:149-151, 171-173`), so long text must be pre-elided
  (gutter) and chip-measured (hover) in C++.
- Track voice state: `MidiTimeline::tracks[t].firstProgram`
  (miditimeline.h:34, `-1` = no program change; engine default program 0).
  `SongView::currentProgram` (trackvoiceops.cpp:177-190) is
  playhead-dependent — deliberately **not** used here. Primary track:
  `selectionModel().primaryTrack()`; roll text reads it
  (timelinequickview_pianoroll.cpp:489).
- Invalidation gap: `SongView::coordinateSelectionChange`
  (songview.cpp:977-987) dirties Note layers on primary-track change but not
  `KeyboardText`/`HoverChip`. Bank/timeline changes already refresh `All`
  (songview.cpp:939, attach path).
- Fixtures: `fixture_rich.inc` slots 10/11 are `voice_keysplit_all
  fixture_drums_a/b`; `fixture_drums_a.inc` fills slots 36 (symbol
  `DirectSoundWaveData_fixture_drum` → name `fixture_drum`), 37 (noise,
  unnamed), 38 (`DirectSoundWaveData_fixture_pluck` → `fixture_pluck`) —
  staged by `voicegroupEditorFiles()` (fixturecatalog.cpp:52-61) and loaded
  by `vgloadcheck` (tst_voicegrouploader.cpp:54).
- Existing gutter coverage: `rollcheck-static`
  `keyboardGutterHoverTracksRows` (rollcheck/static/camera.cpp:475-494)
  drives gutter hover via `CameraFixture` — but its `PianoRollStaticTest`
  slots are declared in `tst_pianorollstatic.h`, so extending it costs a
  fourth file. `timelinepancheck`'s `TimelinePanTest` is defined inside
  `tst_timelinepan.cpp`, its fixture owns a by-value bank + SongTab + Quick
  scene + text-model spies — extendable in one file. No existing check
  asserts `pianoKeyboardTextModel` records or `hoverChipText`.
- **Clipping audit (behavior audit, confirmed):** both hover-chip items —
  `timelineQuickPianoHoverChip` (PianoRollCanvas.qml:109-120) and
  `timelineQuickPianoHoverChipText` (:156-175) — are parented to
  `root.gutterSide`, which is the roll band's `gutterBox`: fixed
  `gutterWidth`, `clip: true` (TimelineCanvas.qml:138-144). A full-width
  chip rect is therefore visibly clipped at the gutter edge. The band root
  (`sceneBand`, :118-136) does **not** clip, and `gutterBox` sits at
  band-local x = 0, so gutter-local chip coordinates are already
  band-local. The roll gutter input item is `timelineRollGutterInput`
  (:254). Precedent for escaping clipped boxes: `RulerControls` takes
  `overlayRoot: root` for its tooltip (:233-241).

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [poryaaaa subgroup slot-name ownership](task-1-brief.md) | SDD-track / sdd-implementer | C heap-ownership surgery in a foreign repo; allocation-failure and parallel-array invariants need review | None |
| 2 | [Porydaw seam: resolve + publish](task-2-brief.md) | SDD-track / sdd-implementer | Free-function helpers over public SongView accessors plus one dirty-union line; no Qt ownership/model/threading surface | 1 (committed sha) |
| 3 | [Gutter/hover scene contract + coverage](task-3-brief.md) | SDD-track / qt-cpp-reviewer | Quick-scene text records, hover chip geometry, elide policy, input-driven Qt check — paint/model-record judgment | 2 |
| 4 | [Unclipped hover-chip overlay](task-4-brief.md) | SDD-track / qt-cpp-reviewer | QML reparenting, band z-order, and clip semantics across two canvases — Quick stacking judgment | 3 |

Tasks 2 and 3 have disjoint write sets; they may run SHARED_TREE. CP1's
controller-owned gitlink update blocks Task 2 (sequential 1 → CP1 → 2);
Task 3 starts only after Task 2's interface lands. Task 4 runs after CP2
checkpoints Tasks 2-3: it consumes Task 3's scene/geometry hover contract
and re-edits `tst_timelinepan.cpp`, whose prior writer must be
checkpointed first (its QML write set is otherwise disjoint from Tasks 2-3).

## Global Constraints

- Every brief inherits this section. Write sets are closed; preserve
  unrelated changes — the dirty tree (`deno.json`,
  `docs/songtab-quick-composition-plan.md`, untracked
  `docs/plans/quick-song-workspace/`,
  `src/ui/songview/quick/composition-prototype/`, `.worktrees/*`) is other
  work; do not touch, format, or stage it.
- `ToneData` layout and all engine-facing `ToneData*` entry points stay
  byte-identical. No audio-thread, `AudioEngine`, `VoicegroupSource` parse,
  or mid2agb changes. No UI-side `.inc` reparsing — metadata is consumed
  from the loaded bank only.
- Subgroup slot names are generic metadata (keysplit **and** keysplit-all
  subgroups get them); Porydaw displays them only for statically-classified
  drumset tracks. A track's classification never changes over its lifetime.
- UI scope is the Quick piano-keyboard **gutter** text + its hover chip.
  No note-face labels. Gutter geometry stays fixed
  (`PianoRollGeometry::resolve` untouched): long labels elide in the gutter
  (`QFontMetrics::elidedText`, `m_geometry.pianoKeyboardLabelRightInset`
  budget), hover shows the full label, unnamed pads fall back to
  `detail::keyName`. All sizes/positions via `layout::` primitives.
- Verification commands are pre-selected below and in each brief; no one
  re-discovers them. Reassess only if the change alters scope or a command
  proves stale/unavailable; report the mismatch and revised command rather
  than silently narrowing.
- Subagents and implementers skip builds, tests, formatters, and linters
  entirely: they confine themselves to their closed write set and read-only,
  file-local inspection. The controller runs every named gate below from the
  Porydaw root after the relevant edits settle; there is no direct
  `cmake`/`ctest`/`xcrun` invocation anywhere in this plan — all porydaw
  builds and checks go through `deno task`, which configures and compiles
  the pinned `external/poryaaaa` (including `poryaaaa_engine`) itself.

## Verification policy

Behavior lives in [spec.md](spec.md). One statement of execution ownership
here: the controller runs all named gates, in checkpoint order — Task 1's
gates at CP1 (gitlink already updated and staged), Tasks 2-3's gates after
both settle (Task 2's predicate is only meaningful against CP1's staged
gitlink, and Task 3 renders through both), Task 4's gates after its QML
overlay and check extension settle.

```sh
# Task 1 gates (controller, at CP1, from the Porydaw root)
deno task build:checks
deno task verify --filter vgloadcheck --verbose

# Task 2 + Task 3 gates (controller, after Tasks 2-3 settle)
deno task verify --filter vgloadcheck --filter timelinepan --verbose

# Task 4 gates (controller, after Task 4 settles)
deno task verify --filter timelinepan --verbose

# Final sweep (controller)
deno task format --check src/ui/songview/detail.h src/ui/songview/detail.cpp src/ui/songview.cpp src/ui/songview/pianoroll_geometry.cpp src/ui/songview/quick/timelinequickview_pianoroll.cpp src/ui/songview/quick/PianoRollCanvas.qml src/ui/songview/quick/TimelineCanvas.qml src/checks/timelinepan/tst_timelinepan.cpp
deno task verify --filter vgloadcheck --filter rollcheck --filter timelinepan --verbose
```

`deno task build:checks` compiles app + checks + mid2agb against the staged
submodule, so the Task 1 loader change is compile-proven in porydaw's own
tree. `rollcheck` (windowed, Windowing::WindowSystem) and
`timelinepan-native` need native desktop access; the others run offscreen.
Filters are substring matches over registration names in
`src/checks/checkcatalog.cpp`.

## Checkpoints

No commit is authorized by this plan alone; checkpoints happen when the user
authorizes persistence.

- **CP1 — poryaaaa ownership boundary (controller action, blocking for
  Task 2):** after Task 1 is accepted, commit and push the change in
  `external/poryaaaa` on `main` (poryaaaa git identity per its AGENTS.md),
  then update the parent gitlink to that sha and stage it from the Porydaw
  root — `tools/poryaaaa_source.ts` resolves the build source and its cache
  key from the submodule's recorded/index sha, so staging is what makes the
  new engine visible to `deno task`. Then run the Task 1 gates above. Task
  2's prerequisites name this sha; no task edits the submodule pointer
  itself.
- **CP2 — porydaw integration boundary (blocking for Task 4):** Tasks 2
  and 3 have disjoint write sets and one shared verification surface;
  checkpoint both together after final review (seam + rendering + check
  ride on CP1's staged gitlink). No intervening per-task commit. The
  checkpoint also gates Task 4's re-edit of `tst_timelinepan.cpp`: its
  prior writer (Task 3) must be accepted and checkpointed first.
- **Final handoff:** checkpoint Task 4's accepted QML overlay + check
  extension with any remaining accepted work after final review; no empty
  checkpoint just to satisfy a marker.

## Source anchors

| Owner | Current |
| --- | --- |
| Subgroup registry | `vg_register_subgroup` voicegroup_loader.c:664; registration call site :2284; free :3763-3790 |
| Discarded names | `parse_sub_voicegroup` stack temp, voicegroup_loader.c:2242-2263; prefix strip `set_voice_display_name` :300-323 |
| Seam | `VoicegroupLease`/`LoadedBankView` voicegroupsource.h:38-95/:448; `SongTab::applyBankView` songtab.cpp:199-201; `SongView::setVoicegroup` songview.cpp:930-940 |
| Classification inputs | `SongView::voicegroup()` songview.h:253; `timeline()`/`selectionModel()` songview.h:242-244; `firstProgram` miditimeline.h:34; playhead-dependent `currentProgram` trackvoiceops.cpp:177-190 (not used) |
| Gutter/hover | `synchronizeKeyboardText`/`synchronizeHoverChip` timelinequickview_pianoroll.cpp:572-611; `keyboardHoverGeometry` pianoroll_geometry.cpp:167-185; width cache pianoroll.cpp:48-50; dirty flags pianorollquick.h:7-21 |
| Invalidation | `coordinateSelectionChange` primaryChanged branch songview.cpp:977-987 |
| Chip overlay (Task 4) | chip items PianoRollCanvas.qml:109-120/:156-175 under `gutterSide`; `TimelineSceneBand` aliases TimelineCanvas.qml:118-136, `gutterBox` clip :138-144, roll input names :253-254, canvas pass-through :256-259; tooltip `overlayRoot` precedent :233-241 |
| Coverage rigs | `TimelinePanFixture` timelinepan/timelinepanfixture.{h,cpp}:55-127; test class + spies tst_timelinepan.cpp:39-131; row math precedent rollcheck/static/camera.cpp:27-53; `vgloadcheck` tst_voicegrouploader.cpp:54; fixtures fixturecatalog.cpp:33-61 |
