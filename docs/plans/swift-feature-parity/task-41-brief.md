# Context

ED10-3: the pitch-bend popup's **mod-wheel lane, resets, snap lattice, controller
scrubbing, and popup key arbitration** (curve A088–A123, all of proof.controller,
lifecycle A016–A032 — the rows task-40 deferred here). Surface: the mounted
`PitchBendPopup` over `src/swift/app/pitchbend/*`. Fork-main `fceecd88`. Most
production paths already exist end to end and are proved, not rebuilt; four real
gaps are repaired first.

1. **Mod-wheel lane + resets (prove)**: `modWheelGraph` (`.controller(1)`,
   PitchBendPresenter.swift:113), `modWheelReset` (QML :437-444 →
   `resetModCurve` :155-162) and note-bounded commits (`commit` :273-284)
   exist. Laws: curve.cpp:286-307 (stroke/undo/note-off), curve.cpp:368-386 +
   controller.cpp:174-192 (resets) — exact predicates in the contract.
2. **Snap lattice (repair)**: the fork quantizes stroke/vertex ticks through
   the live grid lattice — `m_grid->snapTick/snapTickDown`
   (pitchbendgraph.cpp:769-780, Alt ⇒ fine) over a **segment-anchored**
   lattice re-anchoring at every signature seam (grid.cpp:202-216, 328-338).
   Swift ported that lattice (`GridGeometry.snapTick/snapUp`,
   GridGeometry.swift:243-284) but `kernel(for:)` bakes one absolute-anchored
   stride at open time (PitchBendPresenter.swift:259-261) and the kernel
   quantizes on it (PitchBendKernel.swift:148-155, 246-269): points after an
   in-span seam land off-lattice (curve.cpp:333-366) and the stride goes
   stale across camera zoom while open. Alt drags commit a fine-grid ramp
   (curve.cpp:309-331).
3. **Controller scrub/wheel (mostly prove)**: wheel inside the pitch-graph
   canvas raises BENDR one step per 120-unit notch — pitch-only, canvas
   confined, momentum zero, pixel deltas ×5 (fork pitchbendgraph.cpp:422-441;
   PitchBendScene.wheel :114-118 is fork-identical) — through `setBendRange`'s
   note-bounded `.controller(0x14)` write (PitchBendPresenter.swift:164-177 ↔
   pitchbendeditor.cpp:97-112, 223-232); outside the canvas: no write. The
   DragInputs pointer-scrub and advertise `Qt.SizeVerCursor`; LFO writes
   `.controller(0x15)` likewise (controller.cpp:95-168); a stationary click
   on `lfoSpeedInput` focuses + selects text, writes nothing (:131-144).
4. **Popup key arbitration (repair)**: fork law (pitchbendeditor.cpp:606-626,
   pitchbendgraph.cpp:214-247; lifecycle.cpp:105-152) — popup open + graph
   focused: Space (keymap `transport.play_pause`, no autoRepeat) auditions
   from the anchored note's start tick once with no history/SMF change; S
   (keymap `roll.solo_tracks`) is the **only** routed command; M and every
   other roll command is absorbed; Enter and idle mouse never dismiss;
   internal edits + refresh keep the same editor. Swift today:
   `routeUnclaimedKey` handles only Delete/Backspace/Enter/Return
   (PitchBendPresenter.swift:214-228) and the popup claims no
   ShortcutOverride (PitchBendPopup.qml:68-75), so Space/M/S reach the window
   Shortcuts (ShellWindow.qml:179-197) — Space plays from the edit cursor, M
   toggles mute, S toggles solo by accident of scope. The description laws
   already hold via `controllerValues` + the fork-identical description
   string (PitchBendPresenter.swift:286-292) — prove them.

# Exact write set

- `src/swift/app/pitchbend/PitchBendKernel.swift` — lattice-closure init and
  `replace` walk per contract.
- `src/swift/app/pitchbend/PitchBendPresenter.swift` — live-grid closures,
  arbitration routes, the two new callbacks.
- `src/swift/app/DocumentWorkspace.swift` — solo-command wiring.
- `src/swift/app/ApplicationSession.swift` — hot file, audition wiring only
  (:1047-1054 region).
- `src/ui/songview/quick/PitchBendPopup.qml` — ShortcutOverride claim.
- `src/ui/songview/quick/DragInput.qml` — HoverHandler objectName line.
- `src/checks/rollcheck/pitch_bend.swift` — adapt the three kernel
  constructions (:10, :65, :231); new native blocks. Existing predicate
  messages stay byte-identical.
- `src/checks/editorqml/tst_ShellPitchBend.qml` — new functions; existing ten
  stay byte-identical.
- Ledgers (controller-delegated ledger agent, this task's commit):
  `proof.curve.txt`, `proof.controller.txt`, `proof.lifecycle.txt`.

No `PitchBendScene.swift`, `PitchBendGeometry.swift`, `EditorSurface.qml`,
`PianoGrid.swift`, `NoteCommands.swift`, CMake, or registration edits. Sizing
exception: one behavior family (the popup's mod-wheel/controller/keyboard
surface) over 9 files with one verification-surface set — named for the
dispatch table.

# Prerequisites

Task 40 accepted (curve A058–A087, `pitchBendObserveDocument`, the mounted
G/external/preview journeys this builds on). No other interface deps.
Parallel-safe with 38b/45/48 (disjoint write sets; touches neither
EditorSurface.qml nor ThemeColorChecks.swift). Serialize the
ApplicationSession.swift hunk against later 44/46/50 dispatches. macOS host for
the shell lane.

# Interface contract

- `PitchBendKernel.init(lane:geometry:startTick:endTick:fineTicks:snap:snapUp:
  points:endValue:)`; `snap: (Double, Bool) -> Int`, `snapUp: (Double, Bool) ->
  Int` quantize a raw tick (fine = Alt). Contract: `snapUp` never returns less
  than the lattice floor and strictly advances past any lattice point; `snap`
  is idempotent on lattice points. The kernel keeps clamping into
  `[startTick, min(endTick - 1, lastSnapped)]` (PitchBendKernel.swift:152-154)
  and `replace(from:to:fine:)` steps intermediate ticks through `snapUp`. The
  presenter supplies `session.grid.snapTick/snapTickUp(_:camera:fine:)`
  closures so the lattice resolves live per sample — across seams and after
  zoom, matching the fork's `m_grid` pointer semantics.
- `routeUnclaimedKey` additionally: `matches(key, modifiers,
  "transport.play_pause") && !autoRepeat` → `onAuditionFromTick?(Tick(
  note.tick))`; `matches(..., "roll.solo_tracks")` → `onSoloTracksRequested?()`;
  both return true; all other keys keep today's behavior (vertex retry, finish,
  else false — the popup absorbs).
- `PitchBendPopup.Keys.onShortcutOverride`: accepted while open and neither
  DragInput text input holds active focus (bare Space stays
  window-transport-owned inside numeric fields, AGENTS.md); else not accepted.
- Native blocks reuse `pitchBendCheckScene`, `pitchBendStroke`,
  `pitchBendLaneHasPoint`, `pitchBendSyntheticSession`,
  `pitchBendObserveDocument`, `coreTimeBytes`; the suite session is never
  re-wired. New blocks (message-anchored, task-20 style):
  - *Mod stroke*: mod-lane stroke `(0.25, 0.70) → (0.75, 0.25)` → one entry;
    interior `.controller(1)` point > 0; note-off point equals the pre-stroke
    effective value; `undoDocument()` restores exact bytes;
    `documentDidChange` keeps `isOpen`.
  - *Alt ramp*: `pitchBendStroke(0.10, 0.85, 0.90, 0.15, Qt.AltModifier)` →
    one entry; ≥ 3 interior `.pitchBend` points; spacing ≤
    `session.grid.fineGridTicks(camera:)`; strictly increasing; undo restores
    bytes, editor open.
  - *Signature seam*: synthetic session, `addNotes([NewNote(track: 0, tick:
    288, pitch: 61, duration: 384, velocity: 100)])` +
    `setTimeSignature(tick: 480, numerator: 8, denominatorPower: 3)` (the
    fork's denomPow2 parametrization), select, open — `kernel.endTick == 672`;
    stroke `(0.10, 0.80) → (0.90, 0.20)`; every committed interior point
    satisfies `session.grid.snapTick(Double(point.tick), camera:) ==
    point.tick`, ≥ 1 point each side of 480.
  - *Resets*: draw both lanes, capture note-off values, `resetModCurve` /
    `resetPitchCurve` — span all-default, note-off preserved, one entry each,
    editor open; undo restores exact prior bytes and the non-default span.
  - *Wheel*: `presenter.pitchGraph().wheel(angleY: 120 * delta, pixelY: 0,
    momentum: false)` raises `bendRange` by delta, one entry, note-bounded
    `.controller(0x14)` with the pre-wheel note-off value, description shows
    "<n> semitones"; a wheel at an outside point leaves range, index and bytes
    unchanged (the lane's canvas gate mirrors the QML `inCanvas` check).
  - *Controller writes + chaining*: `setBendRange`/`setLfoSpeed` note-bounded
    with end restoration; chained set + set, `undoDocument()` twice steps the
    index back one entry at a time (afterBend, then baseline bytes), `isOpen`
    throughout.
  - *Arbitration*: recorders on both callbacks; `routeUnclaimedKey(Space, 0,
    false)` fires audition once with the note's start tick, no history/byte
    change, autoRepeat suppressed; `(S, 0, false)` fires solo once; `(M, 0,
    false)` returns false (absorbed, not routed).
  - *Refresh*: after wheel + set, call `documentDidChange()` directly — same
    open editor, same `pitchGraph()` object identity.
  - *Active BENDR*: synthetic session with `writeLane(.controller(0x14),
    {{note.tick, 12}})` before open — `bendRange == 12`, description contains
    "12 semitones".
- Mounted functions (helpers `openPitchEditor`/`openViaG`/`waitForNative`):
  - *Wheel*: `mouseWheel(pitch, cx, cy, 0, 120)` → `bendRange` +1, one
    revision, description updates; outside the canvas (corner offset by a
    font-derived margin) → no revision, no range change; 240 → +2.
  - *Scrubs*: press `bendRangeSpin` center, move up
    `appearance.dragThreshold + 2` → exactly +1; Shift-scrub `lfoSpeedSpin` up
    `threshold + 5` → exactly +1; one revision each; undo twice steps both
    back, popup open; distances derive from the published threshold — never
    raw pixels.
  - *Stationary click*: `mouseClick(lfoSpeedInput)` → input `activeFocus`,
    `selectedText` non-empty, revision and `editor.lfoSpeed` unchanged.
  - *Cursor*: `mouseMove` over each spin → its `*ScrubHint` handler reports
    `hovered` and `cursorShape === Qt.SizeVerCursor`.
  - *Idle/Enter*: `mouseMove` across the canvas; `keyClick(Qt.Key_Enter)` and
    `Qt.Key_Return` — `isOpen`, same `findChild` identity.
  - *Space/S/M*: popup open + graph focused: `keyClick(Qt.Key_Space)` →
    `transportToolbar` `presenter.state` leaves stopped with the playhead at
    the note's tick, revision unchanged, popup open; `keyClick(Qt.Key_S)`
    twice → the selected track's solo flag (`timelineHeaderSolo_<track>` /
    headersModel row) toggles then restores, revision unchanged;
    `keyClick(Qt.Key_M)` → mute flag and revision unchanged.
- No sleeps; `tryCompare`/`waitForNative` only; canvas/window fractions and
  published metrics only.

# Implementation steps

1. Kernel: swap `snapTicks` for the `snap`/`snapUp` closures; rework
   `replace`'s walk; keep `fineTicks` stored; adapt the three check
   constructions with stride closures. Closed task-20 rows must stay green.
2. Presenter: live-grid closures in `kernel(for:)`; arbitration routes and
   callbacks; wire DocumentWorkspace (solo) and ApplicationSession (audition).
3. QML: popup ShortcutOverride claim; DragInput HoverHandler objectName.
4. Native predicate blocks (mod stroke, Alt ramp, signature seam, resets,
   wheel, controller writes/chaining, arbitration, refresh, active BENDR).
5. Mounted test functions (wheel, scrubs, stationary click, cursor, idle/Enter,
   Space/S/M).
6. Run the lanes; classify failures: harness artifact → fix predicate; behavior
   gap → stop, report, minimal repair in the write set. Record RED→GREEN for
   the lattice, Space-audition and S-solo repairs (predicates must fail on the
   pre-repair tree); everything else is proof-first.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — native mod-stroke/reset,
  Alt ramp, signature-seam lattice, wheel confinement, controller writes and
  chaining, arbitration, refresh, active-BENDR description, plus all existing
  pitch-bend predicates unchanged.
- `deno task verify:shell --filter shell-pitch-bend --verbose` — mounted wheel,
  scrub, stationary-click, cursor, idle/Enter, Space/S/M journeys plus all ten
  existing tests unchanged.
- `deno task verify:qml-roll --verbose` — EditorSurface/popup-mount regression
  (no EditorSurface edit expected; guards the Loader block).
- `deno task verify:qml --verbose` — DragInput consumer regression (drawer
  prompts share the control).
- `deno task verify:bridge`
- Controller-side after the ledger handoff: `deno task proof check`,
  `deno task proof check --executed`, `deno task proof check
  --strict-mappings`.

# Visual parity

No chrome change: the popup face stays frozen against
`src/checks/fixtures/visual/macos-dpr1-font12/quick/vanilla/pitch-bend-popup.{png,json}`
(task-20 contract). The DragInput line is inert; the ShortcutOverride handler
renders nothing. If any repair touches visible chrome, the controller
re-captures and compares the form regions before accepting.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants (scrub distances from `appearance.dragThreshold`,
  outside-canvas offsets from font-derived metrics); no new published
  check-only properties (the HoverHandler objectName follows DragInput's own
  parametrized-name convention); no new lanes/registrations/debug seams; no
  palette literals.
- The kernel-lattice change must not alter `.clock`/fine quantization observed
  by the closed A001–A057 predicates: `GridGeometry.lattice` ties up absolutely
  for fine/clock, matching the previous arithmetic — the existing
  `pitchBendSharedGridPredicates` block is the regression proof.
- AGENTS.md Space rule: the popup claims bare Space only as an explicit
  audition surface and never while a numeric field inside it holds focus; no
  second dispatcher — routing goes through `routeUnclaimedKey` +
  `KeybindingRegistry` exactly once.
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent in this task's commit. Intended dispositions (message-anchored
  executing predicates; compact form on close):
  - `proof.curve.txt` (agent also rewrites the scope sentence "A088-A123 stay
    GAP" to reflect closure; PARTIAL rows A025/A026/A059 keep their
    dispositions): A088–A089 → open-scene facts; A090–A092 → "a mod-wheel
    stroke writes note-scoped CC1 with interior motion"; A093 → "the mod-wheel
    stroke preserves the note-off lane value"; A094–A096 → "undoing the
    mod-wheel stroke restores the exact prior song bytes with the editor
    open"; A097–A098 → open-scene facts; A099–A101 → "an Alt drag commits a
    fine-grid ramp"; A102 → "fine-grid ramp spacing never exceeds the fine
    stride"; A103 → "the Alt ramp rises monotonically"; A104–A105 → "undoing
    the Alt ramp restores the exact prior song bytes with the editor open";
    A106–A109 → "a note across a signature seam opens its editor";
    A110–A111 → realize/stroke anchors; A112 → "every committed point sits on
    the dynamic snap lattice"; A113–A114 → "committed points straddle the
    signature seam"; A115–A118 → open-scene/draw/reset-realize facts;
    A119–A120 → "the mod-wheel reset pushes one history entry"; A121 → "the
    mod-wheel reset zeroes the lane over the note span"; A122 → "the mod-wheel
    reset preserves the note-off lane value"; A123 → "the mod-wheel reset
    keeps the editor open".
  - `proof.controller.txt` (agent adds the S rows this ledger has never had
    and refreshes the header counterpart/command): A001–A002, A011, A014,
    A019–A020, A027–A028, A035–A036, A043–A045, A056–A058, A068–A069, A076 →
    realize/exposure facts; A003 → "wheeling inside the pitch graph raises
    BENDR one step per notch" (mounted, all three data rows); A004–A005 →
    "wheeling outside the graph canvas writes nothing"; A006–A007 → native +
    mounted wheel anchors; A008 → "the description reflects the active BENDR
    semitones"; A009–A010 → "the wheeled BENDR write is note-bounded";
    A012–A013, A015–A018 → "the scrub fields advertise the vertical scrub
    cursor"; A021–A022 → "scrubbing the bend range pushes exactly one history
    entry"; A023–A024 (A023 PARTIAL→MATCHED) → "a pointer scrub raises BENDR
    by one" + note-bounded anchor; A025–A026 → note-off/editor-open anchors;
    A029–A030 → "shift-scrubbing the LFO field pushes exactly one history
    entry"; A031–A032 → "a shift scrub raises LFO speed by one" + note-bounded
    anchor; A033–A034 → note-off/editor-open anchors; A037 → click anchor;
    A038–A040 → "a stationary click edits nothing"; A041 → "a stationary click
    focuses the field"; A042 → "a stationary click selects the field text";
    A046–A047 → the two scrub anchors; A048–A051 → "the first controller undo
    restores the bend-only bytes with the editor open"; A052–A055 → "the
    second controller undo restores the baseline bytes with the editor open";
    A059–A060 → reset-realize facts; A061 → "the pitch reset pushes one
    history entry"; A062 → "the pitch reset zeroes the curve over the note
    span"; A063 → "the pitch reset restores the note-off value"; A064 →
    editor-open anchor; A065–A067 → "undoing the pitch reset restores the
    drawn curve bytes"; A070 → mounted ShortcutOverride acceptance anchor;
    A071–A072 → "Space auditions from the note's start tick"; A073–A075 →
    "auditioning from the popup changes no document bytes with the editor
    open"; A077 → "M stays absorbed while the popup has focus"; A078–A079 →
    "S toggles solo exactly once while the popup is open"; A080–A081 →
    no-history/no-bytes anchors.
  - `proof.lifecycle.txt` (already-MATCHED rows keep dispositions): A016,
    A019–A020, A023, A026–A027 → open-scene facts; A017–A018 → "the
    description reflects the active BENDR semitones"; A021 → "idle mouse
    movement keeps the popup open"; A022 → same-identity anchor; A024–A025 →
    "Enter does not dismiss the popup"; A028 → wheel anchor; A029–A030 →
    scrub anchors; A031–A032 → "internal edits and refreshes keep the same
    editor open".
  - Disclosed deviations (record, do not code around): native scrub rows
    execute through `setBendRange`/`setLfoSpeed` (the commit entry the
    DragInput writes); the pointer-scrub gesture executes on the mounted lane
    (closing A023's PARTIAL reason); cursor rows assert the production
    HoverHandler's advertised shape and real hover delivery because QML
    TestCase cannot read the window cursor (Qt renders HoverHandler
    .cursorShape on hover); native arbitration rows observe the routed
    callbacks while window-shortcut non-delivery (M) and audible playback
    execute mounted; the signature fixture uses the fork's denomPow2
    parametrization (8 beats over 2^3), not a literal 8/3 fraction.
- Blocked/untouched rows: `proof.vertex.txt` (36) and `proof.raster.txt` (22) —
  later ED10 vertex/raster slice; `proof.lifecycle.txt` A036, A038–A093 (later
  ED10/ED12 slices); `selectionkey/proof.localinputtier_pitchbend.txt`
  (task-50); `proof.fixture.txt` untouched.

# Controller verification

After the writer settles and no check processes remain:

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — curve/controller/lifecycle show
   executing anchors for every row flipped above and none for the untouched
   ranges.
2. Visual: re-run `deno task verify:shell --filter shell-pitch-bend --verbose`;
   the popup face is unchanged against the frozen fixture; if any chrome
   repair landed, re-capture and compare the form regions first.
3. Native smoke (desktop): launch the built app, open a song, click a note,
   press G — wheel inside the pitch graph raises BENDR (description updates),
   wheel outside changes nothing; drag the BENDR field up one scrub and
   Shift-drag the LFO field; hover both fields for the resize cursor; click the
   LFO field (text selects, nothing edits); Space auditions from the note's
   start, S toggles solo, M does nothing; both Reset buttons flatten their
   lanes; Alt-drag draws a fine ramp; a note crossing a changed signature
   commits points aligned to both sides' grids; Escape closes.
