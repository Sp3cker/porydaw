# Task 82 brief — drum-pad names on the mounted roll keyboard

# Context

The roll keyboard still emits only octave-C labels. Build the missing named
pad/fallback surface, driven by the selected track's **initial** program and
its real loaded bank. Moving the edit cursor or playhead across later program
changes must not switch the keyboard's drum classification. This is not the
already-completed generic pan/scroll proof work.

1. **Verified census: 15 GAP behavior rows**, all in
   `src/checks/timelinepan/proof.tst_timelinepan.txt`: A036, A038, A039, A041,
   A042, A043, A044, A061, A064, A065, A069, A080, A082, A085, A087.
   Inspected with `deno task proof sites --area timelinepan --status GAP`
   and `--offset 20`. They cover named/long/fallback text, measured row bounds,
   track-switch disappearance/restoration and classification stability.
   Model-index/fixture guards A028/A034/A035/A037/A055/A071/A072/A073/A077/A090
   and current-program observations A079/A081/A084/A086 are not targets.
2. **Fork laws**, `fceecd88:src/checks/timelinepan/tst_timelinepan.cpp`:
   - `:504-538` resolves `firstProgram`, with -1 falling back to program 0,
     then classifies the loaded top-level `VOICE_KEYSPLIT_ALL` voice.
   - `:541-571` displays full pad names, including accidentals, or pitch names
     for unnamed pads. Label width is the maximum of keyboard width minus
     inset and measured text advance plus inset; x is zero and y/height match
     the projected row. These are visible clipping/legibility laws, not a
     requirement to recreate QModelIndex or QFont identity.
   - `:573-594` uses the same full name in an on-screen, measured hover chip.
     Preserve that behavior while adding the fixed labels even though the
     existing generic-chip rows are already closed.
   - `:645-670` switches to melodic octave-C labels and back to the exact
     drum labels. Prove the exact label contents, not merely a smaller count.
   - `:734-766` forces genuine keyboard synchronization at each cursor/
     playhead position; pad names remain tied to the initial voice while
     current-program context changes. Stale unreconstructed text is no proof.
3. **Current production state**, verified after the split:
   - `src/swift/app/roll/GridScene+Rebuild.swift:365-384` emits only natural
     octave-C `keyName` records. `GridSceneInput` and `StaticKey` at `:8-57`
     have no bank/program label input.
   - `src/swift/app/roll/PianoGrid+SceneSync.swift:15-57` builds that input
     from the real session. `DocumentSession.swift:74-78` already publishes
     the timeline, bank lease and bank slots; the preamble's “no program/bank
     surface” claim is stale. No edit to DocumentSession is needed.
   - `src/swift/app/ProjectService.swift:118-147` publishes `BankSlotView`
     with copied subvoice macro facts but no pad names. `copySlots` at
     `:401-440` already borrows the pinned loaded bank for detached values.
   - The existing native read boundary can supply names without new C++:
     shared poryaaaa `packages/poryaaaa/plugin/voicegroup_loader.h:112-121`
     declares `voicegroup_subgroup_slot_name`; its implementation at
     `voicegroup_loader.c:3888-3906` resolves a registered subgroup. Name
     derivation at `:300-322` strips known symbol prefixes. These files are
     in the main checkout's shared `external/poryaaaa`, not a write target.
   - `src/swift/app/DocumentWorkspace.swift:402-407` refreshes the grid on
     document/selection/scale changes but not bank-only changes. Include bank
     publication in the existing refresh path, not a second observer.
   - `src/swift/app/roll/GridScene.swift:183-247` hardcodes pitch-name hover
     text and width. `src/swift/app/timeline/GridTypography.swift:54-94,
     115-122,150-169` already owns font-metric objects and cached pitch widths.
   - `src/ui/songview/quick/PianoRollCanvas.qml:129-175` mounts keyboard text
     under the clipped gutter-content side. `EditorSurface.qml:388-403`
     applies the vertical camera translation there; `:601-608` supplies the
     unclipped roll-band overlay at the same ruler-relative origin. Keep
     label coordinates in content space, applying the camera once.
   - Real staged fixtures supply named and unnamed pads:
     `src/checks/fixtures/decompproject/sound/voicegroups/fixture_rich.inc:
     13-14` names drum banks at slots 10/11. `fixture_drums_a.inc:3-6` gives
     named sample keys 36/38 and unnamed noise key 37; `fixture_drums_b.inc:
     3-6` adds a named wave at accidental key 37. The adjacent
     `sound/programmable_wave_data.inc:5-7` declares its real waveform bytes.
     Extend this real fixture with a 32-character display name, reusing those
     same bytes, so full-name/overflow proof cannot accidentally use a short
     name that fits the gutter. No injected BankSlotView or stack-allocated bank.

# Exact write set

- `src/swift/app/ProjectService.swift`
- `src/swift/app/DocumentWorkspace.swift` — **hot: sole Group A owner**.
- `src/swift/app/roll/PianoGrid+SceneSync.swift`
- `src/swift/app/roll/GridScene+Rebuild.swift`
- `src/swift/app/roll/GridScene.swift`
- `src/swift/app/timeline/GridTypography.swift`
- `src/ui/songview/quick/PianoRollCanvas.qml`
- `src/checks/rollcheck/keyboard.swift`
- `src/checks/rollqml/tst_TimelinePan.qml`
- `src/checks/fixtures/decompproject/sound/programmable_wave_data.inc`
- `src/checks/fixtures/decompproject/sound/voicegroups/fixture_drums_b.inc`
- `src/checks/timelinepan/proof.tst_timelinepan.txt` — only the 15 selected rows and their predicates.

No new fixture assets, CMake, native code, ShellWindow, ShellPresenter,
ApplicationSession, EditorSurface, PianoGrid.swift, track-header owners or
reserved task-78 files are written. In particular, `ProjectService.swift`
is not `ProjectService+Bank.swift`.

# Prerequisites

The content-space scene and split/path repair in sprint-3 §8 are settled.
Consume the existing immutable bank publication and timeline's
`PlaybackTrack.firstProgram` (`src/swift/core/PlaybackTimeline.swift:38-50`).
This task adds no dependency on task 78's token rules and no new interface
consumed by tasks 79–81. Group A parallel work.

# Interface contract

- Add optional detached drum-pad names to `BankSlotView` (128 indexed names
  for a valid loaded drumkit, absent for non-drum voices). Copy bounded UTF-8
  names while `copySlots` holds its existing native borrow; never retain a
  subgroup/name pointer. Reuse `voicegroup_subgroup_slot_name`, not another
  source parser or C++ shim. Existing parsed voice, tone, synth and subvoice
  macro fields retain their meaning.
- In the existing wave-data fixture, add
  `ProgrammableWaveData_fixture_named_pad_long_label_123` with the same
  `.incbin` as `ProgrammableWaveData_fixture_saw`; point only drum bank B's
  key 37 at that symbol. Its loaded name is the full 32-character
  `fixture_named_pad_long_label_123`. Keep the original symbol and all
  waveform bytes, voice parameters, ordinals and other banks unchanged.
- Resolve keyboard classification from the selected track's `firstProgram`
  (negative means slot zero), never effective cursor/playhead program.
  `PianoGrid.sceneInput()` passes the immutable name value plus a stable
  bank-publication/program identity into `GridSceneInput`; include that
  identity in the existing static input key. Do not compare/measure 128
  strings on every pan or use new timer/guard infrastructure.
- `GridScene.rebuildKeyboardText` emits one label per visible drum row,
  with nonempty bank name or existing `keyName` fallback; melodic mode
  retains octave-C labels. Width/row bounds follow the fork formulas in
  content coordinates. Track/bank changes rebuild the correct labels.
- Add `GridTypography.keyLabelAdvance(_ text: String) -> Double` and
  `chipAdvance(_ text: String) -> Double` over retained native metrics for
  the actual fitted label/chip fonts. Cache name widths with the bank/program/
  typography inputs; no per-pointer/pan font construction or temporary map.
  Preserve the existing `chipAdvance(pitch:)` consumer contract.
- Hover resolves the same displayed pad/fallback name. Its chip stays
  viewport-space, measured and on-screen. Fixed labels may overflow the
  gutter horizontally: host the text under the existing unclipped band,
  with the gutter's one vertical content translation. The clipped keyboard
  input and keyboard-key graphics stay where they are. No double scroll.
- Message anchors: A036/A061 named pad text; A038 full long name; A039 exact
  measured width; A041/A042/A043 left/top/height; A044 pitch fallback; A064
  exact melodic octave-label set (which also proves row reduction); A065
  accidental pad-label absence; A069 restoration; A080/A082/A085/A087 initial,
  moved-cursor, advanced-playhead and reset-playhead classification. Each
  clause gets its own literal, not one “drums work” conjunction.
- Preserve all existing keyboard, audition, pan and hover messages. Existing
  note text, static content-window behavior, hit testing, folding, track
  header current-program behavior and cursor-never-seeks policy stay intact.

# Implementation steps

1. **RED first:** add checks to `runKeyboardChecks` using the real staged
   bank and actual document program-change events. Select drum, melodic and
   drum again; assert exact named/fallback text and row bounds. Current
   octave-only publication must fail the named-pad predicates.
2. Extend the existing detached slot publication and scene input. Route
   bank-only changes through `DocumentWorkspace.sessionDidChange`'s existing
   grid refresh branch. No new DocumentSession observer or state authority.
3. Implement names and measured label/chip geometry with the existing
   typography lifetime and static key. Update only the keyboard text host in
   PianoRollCanvas for overflow; leave input, note layers and camera math intact.
4. Add the mounted `TimelinePan` journey: use the production track/voice
   controls to select the fixture drum program, hover named/unnamed/accidental
   rows, switch tracks, move cursor and playhead past a later melodic change,
   and restore. Force real synchronization with existing viewport/refresh
   inputs so unchanged names cannot be stale-cache artifacts. Observe text
   and readable overflow on the actual rendered surface. The Swift fixture
   separately checks the authoritative document/timeline and exact bounds.
5. Run the acceptance lanes after writers settle; attach only the 15 executed
   anchors in the same surface change. Remove the stale “drum/program stays
   native” commentary in the touched TimelinePan check, not unrelated history.

# Acceptance predicate

Controller-run on the settled built tree, each invocation at most 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — real
  bank-name publication, initial-program policy, exact label geometry,
  track/bank invalidation, cursor/playhead separation and existing keyboard
  regressions; `build/proof-evidence/swiftcore-projectsession.json`.
- `PORYDAW_ROLL_QML_SUITE=tst_TimelinePan.qml deno task verify:qml-roll --verbose`
  — only the mounted TimelinePan suite, including named/fallback hover,
  overflow, track switching and content-space pan smoke;
  `build/proof-evidence/swiftroll-window.json`.

The suite selector is an existing harness feature, not a new seam:
`src/checks/rollqml/RollQmlTests.swift:25-36,100-104,110-126`. Fixtures are
registered at `:38-60`. Keyboard checks run from
`src/checks/workspace/SessionChecks.swift:68`. The runner records evidence
via `tools/run_checks.ts:426-434`. Offscreen QML is real mounted behavior,
not proof of physical-screen DPR; report that visual limit accurately.

# Task-specific constraints

Incorporate **sprint-3 §8 Wave constraints** in full: Swift 6.4 spans/InlineArray/
borrowing and ownership types where appropriate, typed throws and strict
concurrency, no hot-path temporary collections/measurement, two-line comments,
base-font geometry, WCAG AA over parity, sole window keyboard authority/no
bare Space/no forwarding/focus memory, one clause/message, real fixtures/no
test seams, no `Qt.callLater` coalescing or idempotence workaround, approval
for workarounds, deferred menus and parked areas unchanged. No new C++.

This surface owns visible text geometry, so its measured bounds are behavior;
QModelIndex/native-pointer assertions remain out. Use AA-safe palette pairs on
actual natural/black key and overflow surfaces, not hard-coded ink. Do not
reduce this task to presenter labels that remain clipped in production QML.

# Controller verification

After fresh evidence run `deno task proof check --executed`, then separately:

- `deno task proof sites --area timelinepan --status GAP`
- `deno task proof sites --area timelinepan --status PARTIAL`

Exactly the selected 15 GAP rows are expected to become MATCHED. Leave the
other 15 open timelinepan rows untouched; no ledger deletion or representation
sweep. Inspect the mounted named/unnamed and track-switch journey, not just the
model assertions. Preserve the existing resize/pan content-space behavior.
