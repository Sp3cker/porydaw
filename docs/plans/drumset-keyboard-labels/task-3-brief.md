# Task 3: Quick gutter and hover render drum pads

> Historical pre-review dispatch record. Test-rig and helper details below
> were superseded by the canonical final contract in `spec.md` and the landed
> stack-owned `DrumBankFixture` scenarios with asserted preconditions.

## Context

Task 2 published `songview::detail::keyboardShowsDrumPads` /
`keyboardDrumPadName` / `keyboardRowLabel` and the track-switch
invalidation. This task switches the Quick piano-keyboard gutter labels and
the scene-level hover contract to those names for statically-classified
drumset tracks — pitch-name fallback, elided gutter text, full hover text
published through `TimelineQuickScene`, fixed geometry — and adds focused
behavioral coverage in `timelinepancheck`, whose harness already asserts
Quick text-model records and owns a bank-by-value SongTab rig
(TimelinePanFixture, timelinepanfixture.cpp:55-100). Consumes Task 1's
metadata via Task 2's helpers. Producer for Task 4: the scene/geometry
hover contract this task freezes (`hoverChipText` full label, measured
`hoverChipRect`) is what Task 4's unclipped QML overlay renders.

## Exact write set

- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/quick/timelinequickview_pianoroll.cpp`
- `src/checks/timelinepan/tst_timelinepan.cpp`

## Prerequisites

Task 2 interface: the three `detail` helpers, the `primaryChanged` →
`KeyboardText | HoverChip` invalidation, and CP1's staged gitlink.

## Interface contract

- `PianoRoll::keyboardHoverGeometry(int key)` (pianoroll_geometry.cpp:167-185):
  `name` comes from `detail::keyboardRowLabel(*m_sv, key)` instead of
  `midiKeyName(key)`; the hidden-row `nullopt` gate, highlight rect, chip
  font/height, and vertical clamp are unchanged. Chip text width:
  `m_keyboardHoverNameWidths[key]` when `detail::keyboardDrumPadName` is
  empty, else
  `QFontMetrics(m_keyboardHoverChipFont).horizontalAdvance(name)`; the
  chip's left edge clamps at `lyt::space(Space::Zero)` so long names span
  past the gutter at full width. `m_keyboardHoverNameWidths` and the
  pitch-name path stay byte-identical (`pianoroll.{h,cpp}` untouched).
  Scene-level only: the published `hoverChipText`/`hoverChipRect` are the
  contract Task 4's overlay renders — this task changes no QML, and its
  acceptance does not claim the wide chip is visibly unclipped (both chip
  items still live under the clipped `gutterSide` until Task 4 moves them).
- `TimelineQuickView::synchronizeKeyboardText`
  (timelinequickview_pianoroll.cpp:572-598): when
  `detail::keyboardShowsDrumPads(*roll.m_sv)` is false, emit exactly today's
  records (visible white C rows only, `keyName`, existing rect / inset /
  alignment). When true, emit one record per viewport-intersecting visible
  row (black-key rows included — each row is a pad), text
  `detail::keyboardRowLabel(*roll.m_sv, key)` elided right via
  `QFontMetrics(*roll.m_keyboardLabelFont).elidedText(text, Qt::ElideRight,
  int(recordRect.width()))` into the existing record rect
  (`keyboardWidth - pianoKeyboardLabelRightInset`), same key kind
  (`PianoMidiLabel`, keyed by pitch), font, color role, and alignment.
- `tst_timelinepan.cpp`: two new `TimelinePanTest` private slots (the test
  class is defined in this file — no header edit),
  `drumGutterLabelsAndHover()` and `drumGutterTrackSwitch()`, using the
  existing `TimelinePanFixture` lifecycle (`init`/`cleanup`), the
  `labelRects`/`TextModelSpies` idioms, and `checks::events::sendMouse`.

## Implementation steps

1. `pianoroll_geometry.cpp`: apply the hover contract (include
   `ui/songview/detail.h`).
2. `timelinequickview_pianoroll.cpp`: apply the gutter-text contract (it
   already includes `ui/songview/detail.h`).
3. Drum-bank rig in `tst_timelinepan.cpp` (file-scope statics mirroring
   `tst_velocitymodel.cpp`'s by-value keysplit pattern): static
   `ToneData drumTones[VOICEGROUP_SIZE]` with typed pads, static
   `char drumNames[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]` holding a named pad,
   an empty (fallback) slot, and one name longer than the gutter width, plus
   the static pointer arrays a `LoadedVoiceGroup` needs
   (`subGroups`, `subGroupVoiceNames`, counts = 1). A local bank with
   `voices[P].type = VOICE_KEYSPLIT_ALL` and
   `voices[P].subGroup = drumTones`, where `P` is read from
   `fixture.view()->timeline()->tracks[fixture.view()
   ->selectionModel().primaryTrack()].firstProgram` mapped `-1` → `0`, is
   swapped in via `fixture.view()->setVoicegroup(&bank)` (public; refreshes
   `All`), restoring the saved original pointer at test end.
4. `drumGutterLabelsAndHover()`: through `fixture.scene()`, assert the
   `pianoKeyboardTextModel` row count covers every visible row in drum mode
   and per-key texts equal the expected pad names (`TextRole`), the long
   name's record is elided (contains `QChar(0x2026)`, `RectRole` width
   within the gutter budget) while the empty slot's record shows
   `keyName(key)`. Then locate the gutter input the way the fixture and
   `CameraFixture` do (`quickView()->rootObject()->findChild<
   TimelineInputItem *>("timelineRollGutterInput")` — TimelineCanvas.qml:254),
   derive the pad row's center with the `camera().keyHeight()/scrollY()`
   edge formula used by `rollcheck/static/camera.cpp:27-53`
   (`keyAt`/`rowCenter` — public `SongView::camera()`/`quickView()` surface;
   small local copies; gutter-input coordinates are gutter-local, x within
   `pianoKeyboardWidth()`), send `QEvent::MouseMove` over the long-name pad,
   and assert the scene-level hover contract Task 4 consumes:
   `hoverChipVisible()`, `hoverChipText()` equal to the **full** un-elided
   name, and `hoverChipRect()` left ≥ 0 with width ≥ the chip-font advance
   of the name; repeat over the empty slot for the pitch-name chip.
5. `drumGutterTrackSwitch()`: pick a second used track from the timeline's
   used mask (`QSKIP` when fewer than two), call
   `fixture.view()->selectTrack(other)`, and assert the model re-emits
   today's pitch-only shape (white C rows only, `keyName` texts — proving
   Task 2's `KeyboardText` invalidation union end-to-end); switch back and
   assert the pad records return. Do not assert the hover chip here:
   synthetic `sendMouse` does not own the real cursor, and the Quick
   refresh emits `pointerLeave`, clearing `m_hoverKey` (controller-
   observed) — hover content is proven within one classification by
   `drumGutterLabelsAndHover()`, and `HoverChip`-on-track-switch is a
   recorded untested gap (spec coverage map).

Edge cases: rows hidden by the pitch projection get no records (existing
`cHiddenRow` gate); zoomed-tiny rows keep the fitted label font
(`m_keyboardLabelFont` already tracks `keyHeight`); non-drumset tracks stay
pixel-identical to today (elide is identity for pitch names); a drumset-typed
voice with no registered names degrades to all-pitch labels.

## Acceptance predicate

One harness binary covers both new scenarios, the pre-existing pan/gutter
assertions (regression), and — via the `timelinepan` substring filter — the
windowed native twin. Named checks (controller runs them, from the Porydaw
root, after Tasks 2-3 settle):

```sh
deno task verify --filter timelinepan --verbose
```

What the scenarios prove: static classification through the real seam
(`setVoicegroup` → helpers), pad-name records on every visible row with
pitch fallback for unnamed pads, gutter elision to the fixed geometry, the
scene-level hover contract (full text, measured rect, left-edge clamp)
within one classification that Task 4 renders, and `KeyboardText`
invalidation on primary-track switch. Visible rendering of the full-width
chip past the clipped gutter is Task 4's acceptance, not this one.
`timelinepan-native` requires native desktop access; `timelinepancheck`
does not.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Gutter geometry,
fonts, and theme roles unchanged; no QML edits whatsoever — the chip
reparenting that renders the wide chip unclipped is Task 4's write set. Do
not edit `timelinepanfixture.{h,cpp}` — the bank swap, input lookup, and row
math all go through public `SongView` surface; the check restores the
original bank pointer and leaves the fixture's camera untouched.
