# Task 7: Checks sweep

## Context

Consumes Tasks 4–6. Last cutover: remaining harnesses pin `Tick` / `kNoTick` / `kMaxTick`. Also the named-check run for Tasks 5–6 (those harness files live here). Files Task 4 already converted (`tst_songdocument_document.cpp`, `tst_songdocument_songtracks.cpp`, `tst_songdocument_timerange.cpp`, `project/save.cpp`, `selectionkey/corefixture.*`) and Task 2’s `onboardcheck/import.cpp` / Task 1’s new smfcheck slot are omitted unless a later compile forces a brief resize.

## Exact write set

- `src/checks/midi/tst_midismf.cpp`
- `src/checks/midi/tst_midismf.h`
- `src/checks/playback/tst_loop.cpp`
- `src/checks/playback/tst_loop.h`
- `src/checks/playback/tst_xcmd.cpp`
- `src/checks/playback/tst_xcmd.h`
- `src/checks/editcheck/tst_songdocument_logic.cpp`
- `src/checks/editcheck/tst_songdocument_support.cpp`
- `src/checks/editcheck/tst_songdocument_songraw.cpp`
- `src/checks/editcheck/tst_songdocument_songtime.cpp`
- `src/checks/editcheck/tst_songdocument_songnotes.cpp`
- `src/checks/editcheck/tst_songdocument_songranges.cpp`
- `src/checks/editcheck/tst_songdocument_metadata.cpp`
- `src/checks/editcheck/tst_songdocument_songmoves.cpp`
- `src/checks/rollcheck/harness.cpp`
- `src/checks/rollcheck/rollcheck.h`
- `src/checks/rollcheck/identity.cpp`
- `src/checks/rollcheck/keyboard.cpp`
- `src/checks/rollcheck/note_rendering.cpp`
- `src/checks/rollcheck/pencil.cpp`
- `src/checks/rollcheck/pencil_velocity.cpp`
- `src/checks/rollcheck/ruler_loop_menu.cpp`
- `src/checks/rollcheck/scale_editing.cpp`
- `src/checks/rollcheck/scale_fold.cpp`
- `src/checks/rollcheck/scale_projection.cpp`
- `src/checks/rollcheck/selection.cpp`
- `src/checks/rollcheck/resize.cpp`
- `src/checks/rollcheck/timemenu.cpp`
- `src/checks/rollcheck/time_signature_prompt.cpp`
- `src/checks/rollcheck/velocity_prompt.cpp`
- `src/checks/rollcheck/remap.cpp`
- `src/checks/rollcheck/presentation.cpp`
- `src/checks/rollcheck/interlock.cpp`
- `src/checks/rollcheck/static/geometry.cpp`
- `src/checks/rollcheck/static/fixtures.cpp`
- `src/checks/rollcheck/static/gate.cpp`
- `src/checks/rollcheck/static/camera.cpp`
- `src/checks/eventviews/chrome.cpp`
- `src/checks/eventviews/edits.cpp`
- `src/checks/eventviews/eventview_fixture.cpp`
- `src/checks/eventviews/eventview_fixture.h`
- `src/checks/eventviews/playhead.cpp`
- `src/checks/eventviews/viewbuckets_grid.cpp`
- `src/checks/eventviews/remap.cpp`
- `src/checks/clipboard/clipmime_test.cpp`
- `src/checks/clipboard/clipcheck_copy.cpp`
- `src/checks/clipboard/clipcheck_merge.cpp`
- `src/checks/clipboard/clipcheck_fixture.cpp`
- `src/checks/clipboard/laneselection_test.cpp`
- `src/checks/clipboard/selectioncheck_tracks.cpp`
- `src/checks/clipboard/selectioncheck_core.cpp`
- `src/checks/selectionkey/localinput.cpp`
- `src/checks/selectionkey/window.cpp`
- `src/checks/automation/automationcanvaslayout.cpp`
- `src/checks/automation/automationclipboard.cpp`
- `src/checks/automation/automationfixture.cpp`
- `src/checks/automation/automationmenus.cpp`
- `src/checks/automation/automationnodedrag.cpp`
- `src/checks/automation/automationownership.cpp`
- `src/checks/automation/automationpainting.cpp`
- `src/checks/automation/automationparity.cpp`
- `src/checks/automation/automationselection.cpp`
- `src/checks/automation/automationpencil.cpp`
- `src/checks/automation/automationvoice.cpp`
- `src/checks/automation/automationcanvasediting.cpp`
- `src/checks/automation/automationpreviews.cpp`
- `src/checks/automation/automationrouting.cpp`
- `src/checks/automation/automationstroke.cpp`
- `src/checks/automation/automationpointmenus.cpp`
- `src/checks/automation/automationactions.cpp`
- `src/checks/automation/ccdeleteconfirmation.cpp`
- `src/checks/automation/tst_automationediting.cpp`
- `src/checks/automation/hover/hoverfixture.cpp`
- `src/checks/automation/hover/tst_automationhover.cpp`
- `src/checks/automation/domain/tst_automationdomain.cpp`
- `src/checks/automation/domain/xcmd.cpp`
- `src/checks/automation/domain/gestures.cpp`
- `src/checks/automation/presentation/painting.cpp`
- `src/checks/automation/presentation/tst_automationpresentation.cpp`
- `src/checks/automation/presentation/tst_automationpresentation.h`
- `src/checks/automation/raster/interaction.cpp`
- `src/checks/automation/raster/painting.cpp`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/pitchbend/lifecycle.cpp`
- `src/checks/pitchbend/controller.cpp`
- `src/checks/pitchbend/fixture.cpp`
- `src/checks/pitchbend/raster.cpp`
- `src/checks/pitchbend/vertex.cpp`
- `src/checks/pitchbend/curve.cpp`
- `src/checks/drawerpresentation/velocity.cpp`
- `src/checks/drawerpresentation/drawer.cpp`
- `src/checks/drawerpresentation/valueprompt.cpp`
- `src/checks/drawerpresentation/fixtures.cpp`
- `src/checks/drawerpresentation/voice.cpp`
- `src/checks/drawerpresentation/voicemenus.cpp`
- `src/checks/audio/clickrig.cpp`

## Prerequisites

4, 5, 6.

## Interface contract

A local/parameter/field that stores a **position** is `Tick`. A local that stores a **computed end** (`start + duration`, `ViewNote::endTick()`, `noteEndTick`) stays `uint64_t`. Sample asserts stay `uint64_t`.

Tick-domain `UINT64_MAX` / `numeric_limits<uint64_t>::max()` in this write set become `kNoTick` (loop absent, whole-span write, grid open end) or `kMaxTick` (saturation / “huge legal tick”).

`edits.cpp` per spec.md: keep `3000000000ULL`; `tickHighBitExact` accepts `kMaxTick` digits and rejects `kNoTick` digits; `tickHighBitThroughEditor` types `kMaxTick` digits; delete 2^53 comments. Do not keep a pin above `kNoTick`.

`qulonglong(...)` QCOMPARE on positions may remain (promotion). Prefer `Tick` / `kNoTick` where the value is a sentinel.

`tst_midismf.h` gains no extra slots unless Task 1’s slot is missing (it should already exist).

## Implementation steps

1. Convert position storage in the listed files to `Tick`; leave computed-end and sample uint64s.
2. Rewrite tick-domain sentinels to `kNoTick` / `kMaxTick`.
3. Apply the `edits.cpp` boundary rewrite. Do not add new harnesses.

## Acceptance predicate

No listed check still compares a `Tick` to `UINT64_MAX`; `kMaxTick` setData is accepted; `kNoTick` setData is rejected; `3000000000` remains. Named checks: `deno task verify --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: narrowing an `endTick()`-shaped local to `Tick` wraps a legal sum — keep those uint64. Compiler-named file already on this list is in scope; a file not on this list is a brief defect.
