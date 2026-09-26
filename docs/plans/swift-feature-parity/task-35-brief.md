# Task 35 — Roll pointer parity: edit-cursor triggers, hover, and click slop

# Context

User report: the old app did not make the edit cursor follow the mouse, and the
old app had click-slop in the piano grid separating "insert the edit cursor"
from "draw a note". Fork-main `fceecd88` is the reference (read only via
`git show fceecd88:<path>`).

## 1. When the fork moves the edit cursor

`SongView::commitEditCursor(tick)` = `setEditCursorTick(tick)` + `emit
editCursorMoved(tick)` (fork `src/ui/songview.cpp:1172-1186`); the signal is
what seeks playback (fork `src/ui/workspaceui.cpp:222`). The complete trigger
list:

- **Roll-body click** — release of an empty-space press that never crossed the
  draw slop: `releasePendingDrawClick` clears the time selection when the
  release x is inside it, then `m_sv.commitEditCursor(m_grid.snapTick(
  m_pressTick))` (fork `src/ui/songview/pianoroll_gestures_active.cpp:213-221`;
  `insideTimeSelection` is the half-open pixel span `[startX, endX)` of an
  active selection covering the primary track,
  `src/ui/songview/pianoroll_geometry.cpp:78-88`). Nearest-snap
  (`snapTick`), not snap-down.
- **Ruler left click** — release below the sweep slop commits the snapped press
  anchor (fork `src/ui/songview/timeruler_interaction.cpp:189-203`, with
  `setEditCursorTick` preview at 199); the sweep itself starts only at
  manhattan `>= QApplication::startDragDistance()` (113-118).
- **Ruler right click outside a time selection** — commits the exact chip tick
  or grid-snapped background tick when the menu opens (fork
  `timeruler_interaction.cpp:338-341`).
- **Home / `transport.go_to_start`** — `goToStart()` → `commitEditCursor(0)`
  (fork `src/ui/songview.cpp:1188-1194`, binding `src/ui/keymap.cpp:109-110`).
- **Range commands** — duplicate/paste/insert/delete commit the cursor to the
  range boundary (fork `src/ui/songview/rangeedit.cpp:633,670,692,756,793`).
- **Event list row** — click/navigation commits the row tick (fork
  `src/ui/songview/quick/eventlistcontroller.cpp:597-598`).
- **Automation drawer** — an untravelled press parks the cursor (fork
  `src/ui/editordrawer/automationcanvas_gesture.cpp:318`).

Negative invariants (verified, no fork code path moves the cursor): a bare
press-and-hold (`beginPendingDraw` never commits — fork
`pianoroll_gestures.cpp:205-211`); hover (`pointerMove` when idle calls only
`refreshHoverCursor` — fork `pianoroll_interaction.cpp:109-111`); Left/Right
arrows (they nudge notes — fork `keymap.cpp:148-155`); playback follow
(`setPlayheadSample` never touches `m_editCursorTick`); note clicks (armed
`Move`/`Resize` releases with delta 0 are no-ops — fork
`pianoroll_gestures_active.cpp:250-260`).

Swift already has every trigger except the roll-body click:
`RulerMenuPresenter.swift:84-88` and `:274-277` (ruler, with `onSeek` wired at
`ApplicationSession.swift:1047-1051`), `ApplicationSession.swift:147`
(voice-list program), `AutomationInteraction.swift:266` (untravelled press),
`AutomationSelectionCommands.swift:92-129` (range commands),
`EventListPresenter.swift:246` (event rows). Swift adds one non-fork trigger
family: roll hover (item 2). Swift also *replaces* the roll-body click with a
note insertion: `PianoGrid.endPointer` runs `addNote(tick:
snapTickDown(pressTick), duration: snapTicks, pitch:)` when the gesture is
still `.pendingDraw` (`src/swift/app/roll/PianoGrid.swift:699-704`), and
`pencilDraw` in the checks pins click-draws-note
(`src/checks/rollcheck/pencil.swift:71-74`).

## 2. What the fork showed on hover

- **Roll plot:** nothing painted. Idle `pointerMove` updates only the mouse
  cursor shape (custom left/right-edge MIDI cursors, `SizeVerCursor` under the
  `roll.velocity_drag` modifier, otherwise the default) and the RollPlot mouse
  hint (`refreshHoverCursor`, fork `pianoroll_geometry.cpp:284-304`). No hover
  guide, no edit-cursor ghost, no `requestQuickUpdate`.
- **Hover guide lines exist in the fork but are published only by drawer
  lanes**: `publishHover` call sites are exclusively
  `src/ui/editordrawer/automationcanvas.cpp:181` and
  `src/ui/editordrawer/voicechangearea.cpp:314`; the owner enum is
  `{None, Automation, VoiceChanges}` (fork
  `src/ui/songview/quick/timelinequickview.h:46-50`). The roll never publishes,
  so while the pointer is over the roll the edit chrome stays visible and
  stationary (hover chrome renders `hoverVisible && bandVisible`, edit chrome
  `editVisible && !hoverVisible` — fork
  `src/ui/songview/quick/TimelineCanvas.qml:96-114`; every scene band mounts
  both, `TimelineCanvas.qml:172-177`).
- **Gutter (keyboard column):** row highlight + pitch-name chip
  (`setHoverKey`/`keyboardHoverGeometry`, fork
  `pianoroll_geometry.cpp:166-199`) — gutter-only, never the plot.

Swift divergence: `EditorSurface.qml:498-501` publishes a roll-owned hover
guide on every no-button move (`playheadGuidesPresenter().updateHover(x)`),
cleared on exit (`:478-484`), and `PlayheadGuidesPresenter` hides the edit
guide while any hover is visible (`PlayheadGuides.swift:169-177`,
`editVisible = … && !hoverVisible`). With a roll hover always live, the dashed
hover line tracks the pointer and the edit line disappears — the reported
"edit cursor follows your mouse". Swift's owner enum also has a `.roll = 3`
case the fork lacks (`PlayheadGuides.swift:12-17`). The gutter chip and
cursor-shape paths already match the fork (`PianoGrid.updateHover:816-834`,
`cursorKind`; gutter hover checks already ported in
`src/checks/rollcheck/static/camera.swift`).

## 3. The fork's click-slop laws and per-target matrix

Threshold laws (fork):

- **Draw slop (PendingDraw → Draw): horizontal only,
  `|x - pressX| >= layout::space(Space::One)`** — resolved in
  `resolveDrawPress` (fork `pianoroll_gestures.cpp:222-232`); before the
  threshold a row change re-auditions (glissando) but never draws.
  `space(Space::One)` = `max(1, round(baseFontPx * 0.25))`
  (`src/ui/layout.cpp:45` multiplier table, ordinal 2 = 0.25; `resolve` at
  `:70-77`). Swift's `GridMetrics.drawThreshold = fontPx(b, 0.25)`
  (`src/swift/app/timeline/GridGeometry.swift:85`, `fontPx` at `:4-6`) is the
  identical law — keep it, no change.
- **Velocity drag (PendingVelocity → Velocity): vertical only,
  `|y - pressY| >= QApplication::startDragDistance()`** (fork
  `pianoroll_gestures.cpp:234-246`). Swift hardcodes `10`
  (`PianoGrid.swift:680`) — replace with the published platform value.
- **Right band / time-sweep (PendingMenu → Band/TimeSel): manhattan
  `>= QApplication::startDragDistance()`** (fork
  `pianoroll_gestures.cpp:213-220`). Swift hardcodes `threshold: 10`
  (`PianoGrid.swift:750`) — same replacement.
- **Note body/edge presses arm Move/Resize immediately — no slop**, and a
  zero-delta release is a no-op (fork `armNoteDrag:177-193`,
  `commitMoveDrag:250-260`).
- `QApplication::startDragDistance()` in the Quick world is
  `Qt.styleHints.startDragDistance`; the fork's own QML reads exactly that
  (`EventListPage.qml:579`, `TimelineScrollbar.qml:223`), and Swift already
  has the publish convention (`AutomationPage.qml:185` pushes
  `Qt.styleHints.startDragDistance` through `configureBody`; policy default 10
  in `AutomationPagePolicy.dragDistance`).

Per-target matrix (press / move / release), fork semantics with the Swift gap:

| Target | Press | Move past slop | Release within slop | Release past slop |
| --- | --- | --- | --- | --- |
| Empty plot, any modifier | `beginPendingDraw`: **clear note selection unconditionally** + audition row at `lastVelocity` (gestures.cpp:205-211) | glissando audition on row change; `|dx| >= space(One)` → `beginDraw` (no re-attack of the sounding key, gestures.cpp:255-274) | **clear time selection if release x inside it; commit cursor at `snapTick(pressTick)`; stop audition** (gestures_active.cpp:213-221) | commit drawn note, select it; cursor untouched (gestures_active.cpp:240-248) |
| Note body | select-if-needed + audition + arm Move (gestures.cpp:130-149) | snapped move preview | zero-delta no-op; note stays selected | commit move |
| Note body + Ctrl (`roll.velocity_drag`) | `PendingVelocity` + audition (gestures.cpp:136-143) | `|dy| >= startDragDistance` → live velocity drag | deferred selection click (Ctrl toggles, gestures_active.cpp:223-238) | commit velocity, latch `lastVelocity` |
| Note edge | select + arm Resize/ResizeLeft | snapped resize preview | zero-delta no-op | commit resize |
| Right on empty | `PendingMenu` | manhattan `>= startDragDistance` → Band (Shift → TimeSel) | note-hit → select + note menu; inside time selection → time menu; else **clear note + time selection**; cursor untouched (gestures_active.cpp:195-211) | commit band/time selection |
| Right press during a held PendingDraw | pending menu; pending draw survives (interaction.cpp:107-126) | band may select | left release still parks the cursor unless a live right drag exists then (interaction.cpp:183-192; interlock.cpp:118-131) | — |
| Middle | pan | pan | end pan | — |
| Double-click empty | `beginDraw` immediately, grid-sized (interaction.cpp:48-74) | sizes the note | — | commit note |
| Double-click note | delete note + clear selection (interaction.cpp:62-69) | — | — | — |
| Off-scale empty press under scale-fold | rejected: no pending draw, no cursor park (gestures.cpp:106-111) | — | — | — |

Swift gaps against this matrix: click adds a note instead of parking the
cursor; no press audition/glissando/no-re-attack; empty-press selection clear
is modifier-gated (`PianoGrid.swift:635-637`) instead of unconditional; no
time-selection clear on click; `doublePointer` ignores empty space
(`PianoGrid.swift:808-814`) so after this task the double-click draw must be
restored or click-drawing is lost entirely; velocity/right thresholds are
hardcoded 10. The PendingDraw park gate must follow the fork's `!dragLive()`
rule — park unless a live right band is active at release — replacing the
permanent `pendingDrawInterrupted` suppression (`PianoGrid.swift:738,700`).

# Exact write set

- `src/swift/app/roll/PianoGrid.swift` — pointer methods only:
  `beginPointer` (unconditional clear, press audition, dragDistance),
  `updatePointer` (velocity slop from `dragDistance`, pending-draw glissando
  audition), `endPointer` (click park: time-selection clear, cursor commit +
  `onCommitCursor`, audition stop, live-right gate), `beginRightPointer`
  (threshold from `dragDistance`), `doublePointer` (empty-space draw);
  publish `dragDistance` and read-only `drawThreshold` as tracked facts;
  add `onCommitCursor`/`onClearTimeSelection` callbacks next to `onAudition`
  (:65-72) and `timeSelectionSource` (:312).
- `src/swift/app/timeline/PlayheadGuides.swift` — delete `.roll` owner case,
  `updateHover(contentX:)` (:114-116) and `clearHover()` (:139-141); keep the
  owner-based API (automation/voiceChanges owners, exercised by
  `bootstrap.guideHover`).
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — `rollInput` MouseArea
  only: drop the hover-guide publish (:500) and exit clear (:482, keep
  `clearKeyboardHover`); push `Qt.styleHints.startDragDistance` into
  `gridModel.dragDistance`.
- `src/swift/app/ApplicationSession.swift` — next to the `rulerMenu.onSeek`
  wiring (:1047-1051) and `grid.timeSelectionSource` (:1056): wire
  `grid.onCommitCursor` → `seekToTick(tick, in:)` and
  `grid.onClearTimeSelection` → `automationPage.clearTimeSelection()`.
- `src/checks/rollcheck/selection.swift` — extend `checkThresholdDrawCell`
  (:493-543, rebased on task 34's stride re-expression): below-threshold
  no-note + cursor-park branch; press-audition/glissando predicate.
- `src/checks/rollcheck/pencil.swift` — `pencilDraw` becomes the fork gesture
  (click parks, then `doublePointer` + release draws).
- `src/checks/rollcheck/interlock.swift` — add the PendingDraw park assertion
  and the time-selection conjuncts the `:90-94` comment marks unproven.
- `src/checks/editorqml/tst_ShellGridInput.qml` — mounted failing-first
  predicates (below).
- `src/checks/rollqml/tst_SwiftRollPlayhead.qml` — roll-hover-never-publishes
  predicate; fix the owner-raw-values comment (:33).

No GridGesture.swift structural edits (the threshold guard at :105 already
carries the law); GridGeometry.swift untouched (drawThreshold already lawful).

# Prerequisites

Sequence after tasks 32, 33, 34a and 34b. Overlaps (agreed with Brief34Grid):
task 32 edits `PianoGrid.swift:1143-1145` and `EditorSurface.qml` font regions
— disjoint from the pointer methods and `rollInput`; task 34a re-expresses the
snap strides inside `GridGesture.swift:111,116,131` and **rewrites
`selection.swift:501-516`**, the same `checkThresholdDrawCell` this task
extends — this brief must rebase on 34's landed version; task 34b edits
`PianoGrid.swift:476-488,539-587,322-329` (menu/commands, `configureViewport`
preservation) — keep `dragDistance` a standalone tracked property, not a
`configureViewport` parameter, to stay off that region. Task 34b's
`EditorSurface.qml` GridRowControl edits (:583-638) are disjoint from
`rollInput` (:402-503).

# Interface contract

- Edit cursor: the roll body commits the cursor only on a
  within-slop `.pendingDraw` release, at
  `metrics.snapTick(state.pressTick, camera:)` (nearest snap), gated by "no
  live right band at release", preceded by clearing the time selection when
  the release tick lies inside `timeSelectionSource?()`'s active range
  (`AutomationTimeSelection.contains`), followed by an audition stop and the
  `onCommitCursor` seek callback. No press, hover, drag commit, note click,
  arrow key, or playback path writes `session.editCursor` from the roll.
- Hover: pointer moves over `swiftRollInput` update `hoverKey`/`cursorKind`
  only; `guides.hover` never publishes from the roll and `guides.edit` stays
  visible at the cursor tick. The `.roll` owner case and its convenience
  methods no longer exist; automation/voiceChanges owner publication semantics
  are unchanged (drawer-lane publication itself is a separate unported fork
  behavior — see Visual parity).
- Click slop: PendingDraw → Draw at `|dx| >= drawThreshold` (unchanged law,
  now published for QML); PendingVelocity → Velocity at
  `|dy| >= dragDistance`; PendingMenu → Band at manhattan
  `>= dragDistance`; `dragDistance` defaults to the policy seed 10 and is
  pushed from QML as `Qt.styleHints.startDragDistance`.
- Empty-space press clears the note selection unconditionally and auditions
  the row at `lastVelocity`; row changes while pending re-audition
  (glissando); crossing the draw threshold does not re-attack the sounding
  key; release/double-click/cancel stop the audition.
- Double-click on empty space draws one grid-sized note (committed on
  release, drag before release sizes it); double-click on a note deletes it
  (existing `doublePointer` branch, unchanged).

# Implementation steps

1. Write the failing predicates first (mounted QML + presenter-level); record
   the RED output.
2. Remove the roll hover publication (EditorSurface calls + `.roll` owner in
   PlayheadGuides) and add the playhead predicate's GREEN proof.
3. Port the PendingDraw press/release semantics: unconditional clear, press
   audition + glissando + no-re-attack, click park with time-selection clear,
   `onCommitCursor`/`onClearTimeSelection` wiring, live-right release gate.
4. Restore `doublePointer` empty-space draw; convert `pencilDraw` to the
   double-click gesture.
5. Replace the hardcoded 10s with the published `dragDistance`; publish
   `drawThreshold`.
6. Run the lanes below; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (selection, pencil,
  interlock lanes)
- `deno task verify:shell --filter shell-grid-input --verbose` (mounted
  pointer predicates)
- `deno task verify:qml-roll --verbose` (playhead guides; EditorSurface
  touched)
- `deno task verify:qml --verbose`
- `deno task verify:bridge`
- Manual: with the app stopped, click empty roll space — cursor line moves to
  the clicked cell, no note appears; drag past ~3px — note draws; sweep the
  pointer while idle — no dashed hover line, edit line stays put.

# Port list (fork assertion → Swift predicate)

| Fork check (file:line) | Pins | Swift predicate |
| --- | --- | --- |
| `selection.cpp:203-204` undo count unchanged on plain click | click never edits the document | `tst_ShellGridInput` click test: `noteSummary` + history unchanged across press/release; `selection.swift` history-count expect |
| `selection.cpp:205-207` cursor parks at `snapTick(tickAtContentX(x))` | click = cursor commit (nearest snap) | `grid.editCursorTick === cell.tick` after within-slop release (mounted + `selection.swift`) |
| `selection.cpp:186-199` press audition, glissando, release stop | pending phase sounds the row | `selection.swift` audition-callback capture (presenter level) |
| `selection.cpp:212-227` `startDragDistance + 8` pull commits the note without re-attack | press grows into draw | `checkThresholdDrawCell` above-threshold branch (existing `dragX = pressX + 8`, rebased) |
| `selection.cpp:302-331` below `space(One) - 0.5` draws nothing; at `space(One)` one snap cell | draw slop law | `checkThresholdDrawCell` new below-branch + mounted move-by-`drawThreshold - 0.5` / `drawThreshold` sequence |
| `selection.cpp:413-445` `+2px` Ctrl-jitter stays a click; `startDragDistance` starts velocity | velocity slop law | `selection.swift` deferred-modifier/velocity checks moved onto `dragDistance`; mounted right-jitter variant |
| `interlock.cpp:40-41` band warmup `startDragDistance + 1` | right slop law | `interlock.swift` band warmup distances; mounted right-press move `< dragDistance` keeps menu, `>=` band-selects |
| `interlock.cpp:118-131` PendingDraw release keeps band selection and parks | interlock park gate | `interlock.swift` new park expect after the right-band release |
| `keyboard.cpp:474-476` click inside time selection clears it | click's time-selection clear | `interlock.swift` time-selection conjuncts (seeded `timeSelectionSource`); mounted variant |
| `harness.cpp:298-304` `drawNote` = DblClick + release | double-click draws | `pencil.swift` `pencilDraw` as click + `doublePointer` + release; mounted `mouseDoubleClickSequence` |
| `pencil_velocity.cpp:280-285` double-click deletes | double-click delete | existing `doublePointer` note-delete predicate (unchanged) |
| `static/camera.cpp:484-492` gutter hover rows, leave clears | hover is gutter-only | existing `camera.swift` port (regression only) |
| `timeruler_interaction.cpp:189-203, 338-341` + `gate.cpp:241-313` | ruler triggers already ported | existing `gate.swift`/`ruler_loop_menu.swift` (regression only) |
| Production `pianoroll_interaction.cpp:109-111`, `timelinequickview.h:46-50` | hover never publishes from the roll | `tst_SwiftRollPlayhead` roll-hover predicate: after `mouseMove(rollInput, …)`, `!guides.hover.visible && guides.edit.visible` |

# Visual parity

Counterpart surfaces: fork `TimelineCanvas.qml:96-114` (chrome visibility
law), `timelinequickview.cpp:582-639` (guide publication), fork
`pianoroll_geometry.cpp:284-304` (hover = cursor shape). No color or segment
layout changes here: `SharedPlayhead.qml` keeps all hover segments mounted
(the fork mounts hover chrome on every scene band); only the publication
source changes. Known adjacent divergences out of scope: the drawer lanes do
not yet publish hover guides the way fork automation/voice-change lanes do
(fork `automationcanvas.cpp:181`, `voicechangearea.cpp:314`); the ruler sweep
slop is snapped-tick-based rather than `startDragDistance` manhattan
(`RulerMenuPresenter.swift:255-268` vs fork
`timeruler_interaction.cpp:113-118`); the ruler right-click commits on press
rather than release (`RulerMenuPresenter.swift:84-88` vs fork
`timeruler_interaction.cpp:316-341`). Report, do not fix here.

# Task-specific constraints

- No C++, no code comments, no pixel constants: thresholds come from
  `drawThreshold` (base-font law, unchanged) and `dragDistance`
  (`Qt.styleHints.startDragDistance`, the fork's `QApplication::
  startDragDistance` equivalent, published per the `AutomationPage` pattern).
- No WCAG surface changes (no text/contrast edits).
- No proof-ledger edits by the implementer. Ledger rows the controller's
  ledger agent should re-disposition after this task: `proof.selection.txt`
  A018, A019, A020, A021 (press-audition/park family GAP → MATCHED), A029
  (below-threshold no-note: delete the documented-divergence mapping text,
  GAP → MATCHED), plus A015-A017 audition rows; `proof.keyboard.txt` A056
  (click clears time selection); `proof.interlock.txt` A003/A005
  time-selection conjuncts and the park rows; `proof.pencil.txt` rows whose
  mapping cites `pencilDraw`-as-click (reason text moves to the double-click
  gesture, disposition unchanged). `swiftrollgated/proof.gesturechecks.txt`
  drag-based rows are unaffected.
