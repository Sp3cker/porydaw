# Next-sprint plan: existing-surface parity after task 36

Status: **planning evidence for the controller.** This file queues behavior-sized work
(tasks 37 onward) for the authorized existing-surface scope, lists plan.md rows made stale
by tasks 19–36, and frames the deferred tracks the user can authorize next. Individual
task briefs are frozen one at a time by the controller; none are written here. Reference
app: fork-main `fceecd88` (read via `git show fceecd88:<path>`). Assessment tree: `2503f41e`
plus the uncommitted task-36 settings cutover.

## 1. Objective and success criteria

Continue the user-authorized scope — details of existing surfaces, visual parity with
`fceecd88`, sizing only through base-font multiples, WCAG AA over parity — until the
remaining authorized behavior gaps are closed. Success per task: a mounted Swift/QML
surface reproduces the fork behavior, its proof-ledger rows move to MATCHED with executing
predicates, the covering AGENTS.md lanes pass, and the controller accepts. Sprint-level
success: no authorized existing-surface family remains GAP for *behavior* (proof-mapping
debt may remain only where a lane cannot execute), and the user has one authorization
decision queued (section 4).

## 2. What landed (tasks 19–36) and stale plan.md rows

Task→commit map (verified in git log `95aae864~20..HEAD`):

| Task | Commit | Outcome |
| --- | --- | --- |
| 19 ED09-1 | `c47e83d2` | Event List cell-edit commit + insert-copy parity |
| 20 ED10-1 | `03df718c` | Pitch-bend stroke/history/span/SMF contract (curve A001–A057) |
| 21 ED07 | `60d05156` | Automation point-menu focus/render/prompt contract |
| 22+23 | `2c7e3065` | Event List theme/summary strings + shared voice short names |
| 24 SH05 | `639c96ff` | Fork window title (dirty) + PCM/CGB/lost-note meter |
| 25 | `f7c32ee6` | Automation ink, tab roles, loop glows, themed ghosts |
| 25b | `b1113abd` | Transport glyphs, grid combobox row, close glyph, mono pitch readout |
| 26 | `63736872` | Fork chunk labels; Event List replaces only the roll band |
| 27 | `a3186010` | Other-events band below the drawer |
| 28 | `d34d93fa` | Event List typography + font-derived columns |
| 29–33 | `4a0e7c42`/`95aae864`/`040dde2a`/`11c58df4` | One Typography/LayoutSpace authority, all surfaces migrated |
| 34a/34b+35 | `780027e3` | Fork grid denomination (Auto/1/N/Clock, Ctrl+1/2/3, per-tab) + roll click slop/cursor parking |
| — | `2503f41e` | Footer status-bar height follows fork law |
| 36 SH06/PJ07/AU05 | **uncommitted WIP** | Swift-owned CFPreferences settings store (not stale until accepted) |

Stale plan.md rows for the controller to update (all still read `pending`; none of this
claims completion — each now has landed slices): **SH02, SH04, SH05, AU03, AU04, ED01,
ED02, ED04, ED05, ED06, ED07, ED09, ED10, ED12, P1, P5, P6, P7.** SH05 is clearest:
shipped by task 24 (`639c96ff`), residual = native macOS dirty dot. R29's wording ("task
21 starts ED07") is outdated — landed. inventory.md is similarly stale (SH05 says "Shell
title is static"; SH06 cites `TransportBar.qml:345-348`). Deliberately **not** stale:
SH01/SH03/SH06, VG01/VG02/VG04/VG05, AU05, PJ05/PJ07 (task 36 WIP or untouched behavior).

## 3. Remaining-gap census, authorized surfaces only

Census of `src/checks/**/proof.*.txt` (186 files; 5045 GAP / 1774 PARTIAL / 5114
MATCHED). Deferred families excluded: samplecheck (~411 GAP, P4), onboardcheck (~446 GAP,
P2), `proof.tst_midiexport.txt` (P3). Counts = GAP+PARTIAL. Raw counts overstate behavior
gaps: preamble text goes stale once a surface lands (e.g. `proof.tabs_scale.txt` says "no
scale selector" while `TransportBar.qml:231-313` mounts one; pitchbend ledgers say "not
ported" while `PitchBendPopup.qml` + `src/swift/app/pitchbend/` exist).

| Family | Open rows | Class | Highest-leverage theme |
| --- | --- | --- | --- |
| Time selection & ruler/time menus | 149 (+94 clipboard) | **behavior** | Swift session owns no time-selection state (`ApplicationSession.swift:525,1063,1362` derives it from the automation page); fork owns it in `songview::EditorSelectionModel` (`src/ui/songview/editorselectionmodel.h:23-76`). Blocks timemenu (69+6), ruler_loop_menu (60+13), and clipboard selectioncheck_tracks (80+14 — its preamble names this root cause) |
| Pitch-bend editor | 300 | behavior + stale text | task-20 deferrals: anchoring/lifetime A058–A073, external-edit preview A074–A087, mod-wheel/reset A088–A096+A115–A123, Alt/fine-grid/sig snapping A097–A114; controller wheel CC14/CC15 scrub (`pitchbend/controller.cpp:39-110`, 80+1); vertex interactions (36) |
| Shell menus & actions (SH01) | — | **behavior** | Menu topology and context-menu shape diverge (section 5, task-46/39); one real misbinding: event-list row menu bypasses canonical dispatch (`EventListMenus.swift:148-154` direct `moveRawEvent` vs `ShellPresenter.swift:275-281` `performEventListCommand`) |
| Event List edits | 113 + remap 27 | behavior | task-19 deferrals: `rawTempoAtomic` 26, `sameTickReorder` 21, `deleteMatrix` 14, `drawerClickAfterEditOwnsDelete` 13 |
| Shared bank (VG05) | viewcache 57+2 | proof-first | Core is strong (`SharedBankState.swift:1-93`, `VoicegroupStore.swift`, `bank_sharing.swift:10-137`; voicegroupbank A019–A021 MATCHED); missing = mounted two-tab UI journey (captions, dirty/close gate, audio). Do not rewrite the store |
| Automation | ~250 | behavior slices + proof depth | task-21 deferrals (second-track fixture, cross-surface invalidation, raster lane, two-point CC) + canvaslayout 62+37, ccdelete 37+17, taptempo, ownership |
| Scale-aware editing | 110 | behavior | fold keyboard nudges, multi-note mapping, off-scale degree motion (scale_editing 31+4, scale_projection 15+9, scale_fold 11+2, tabs_scale 38) |
| Polyphony (AU04) | 46 | **behavior + proof** | two consumer-visible mismatches: single-click event jump vs fork double-click (`PolyphonyPanel.qml:285-310` vs `polyphonypanel.cpp:~360-370`); binary flash vs fork ~1s alpha fade (`polyphonypanel.cpp:598-620`); then jump/reset/cap/lifecycle rows |
| Transport/preferences (SH06) | tabs_transport 42+3 | behavior | `followPlayhead` + `dsp/resonanceSuppression` setter-only (`TransportBarPresenter.swift:174-185`); `windowGeometry`/`windowState`/`songFilter*` have no Swift path; output-dial drag law differs (fork incremental global-Y `transportbar.cpp:38-70`) |
| Track headers (ED03) | 137 | behavior + proof | fork over-budget title/subtitle dimming missing (`trackheadermodel.cpp:241-258` branch absent from `TrackHeadersGeometry.swift:220-280`); meter/menu real-surface proof (activitymeter 16+27, menu 23+10, mutations 17+34) |
| Drawer velocity (ED06) | ~270 PARTIAL-heavy | mostly proof depth | predicates don't read the built timeline projection; real-delegate input/zoom geometry remain — following-sprint backlog |
| Roll render (SH02) | 50 | behavior | `velocityColorRaster` 11, `noteNameRaster` 11, `velocityValueRaster` 8 — fork `SongView::noteColor`/`velocityNoteColor` ramp (`songview.h:337`, `trackvoiceops.cpp:175`) vs GridPalette identity `noteFill` |
| Keyboard (ED12) | 119 | proof + behavior | windowtier_keyboard 70+13; every cancellation cause |
| Project/workspace (PJ05) | ~390 | mixed | workspace 83+17, iomutations 43+54, identity 17+35, save 1+34 — ordered-save/conflict predicates; following sprint |
| Native/host (P8) | ~290 | native-host proof | hostintegration 89, swiftqtml 78, hostadapter 65+15 — need macOS host observation |
| Shell routing proof (SH01/ED12) | 572 | mapping debt | mainwindowrouting state/input/lifecycle — "no executing check" dominates; rides with surface tasks, no standalone pass (POLICY) |

## 4. Authorization candidates (user picks one; none authorized yet)

1. **VG03 create/copy bank** (P5, gates P2) — freeze first: layout-capability detection
   (per-file vs monolithic), naming/collision rules, copy/template semantics, undoable
   assignment + bank rebind/history (spec.md:52, inventory VG03). Deps: existing bank
   owner only. ~3–4 tasks. Cheapest unblock; removes the dock's dead New button.
2. **P3 WAV export** — freeze first: immutable capture of unsaved doc + effective bank +
   settings, lease lifetime, cancellation/file-publication, stop-playback-before-render,
   loop/fade/tail laws, suppression pre-roll/zero-flush; one production renderer replacing
   `ExportChecks.swift`'s private one (spec.md:38–47, verification.md EXPORT). Deps:
   **VG05 frozen first** (task-37 closes it); playback/lease owners exist. ~6–8 tasks.
3. **P7-SH03 theme controls** — freeze first: fork `ThemeDialog` parity (preset chooser,
   system-font control, grid contrast; `src/ui/themes/*`) on the landed Typography
   authority + GridPalette + task-36 PreferencesStore; WCAG AA beats parity. Deps:
   task 36. ~2–3 tasks. Small, parallel-safe.
4. **P2 New Song/MIDI import** — freeze first: create/import transaction write order,
   partial-success/refusal, identity refresh, dirty-tab/close interplay (plan.md
   onboarding prerequisite). Deps: **VG03**. ~6–8 tasks.
5. **P4 Sample Studio** — decoder strategy decision (C seam or Swift DSP), immutable
   source, dialog-local undo, commit/registration order, provenance/sidecar
   (spec.md:5–36). Deps: VG05 + P5 return paths. ~14–18 tasks. Largest; last.

**Recommended: authorize VG03 + P3 together once task-37 (VG05) is accepted** — VG03 is
the cheap P2 unblock; P3 is the highest-value bounded track and depends only on the VG05
policy this sprint freezes. SH03 any time after task 36. P2 follows VG03; P4 last.
Scope question for the user (not authorized here): wiring `file.register_song` to the
existing `SongDockController` registration flow — fork ships it as a File row
(`mainwindow.cpp:304-307`); plan.md currently defers it under PJ02/P2.

## 5. Ordered queue, tasks 37–50

Hot files (serialize): `ShellWindow.qml`, `ApplicationSession.swift`,
`EditorSurface.qml`, `PianoGrid.swift`, plus task-36's `ShellPresenter.swift`/
`TransportBar.qml`/`EditorDrawer.*` until it lands. Shared verify baseline (AGENTS.md):
`deno task build:checks`, `deno task verify:bridge`, `deno task proof check`,
`deno task format --check`; per-task lanes below. **Ready to brief immediately after
task 36: 37, 39, 40, 43.**

- **task-37 — VG05 shared-bank two-tab journey (prove, then repair)** *(ready)*
  Outcome: two real `SongTabsController` tabs resolve to one bank; editing a voice
  through the mounted voicegroup UI in tab A updates tab B's bank view, captions,
  dirty/close gate and audio; close/rebind/save/undo isolation proven. Core is strong —
  do **not** rewrite the store. Fork: canonical bank per voicegroupId, immutable views
  (`src/project/decompproject.h:136-173`, `workspaceui_tabs.cpp:185-193`). Current:
  `SharedBankState.swift:1-93` weak-subscriber propagation, `bank_sharing.swift:10-137`
  two-session checks (voicegroupbank A019–A021 MATCHED); missing piece is the mounted
  two-tab UI journey — `SongTabsController.swift:295-305,502-547` is the seam. Ledgers:
  voicegroupbank fixture/ingress rows, workspace bank rows; closes VG05 and freezes the
  shared-bank policy P3/P4 need. Write-set: `SongTabsController.swift`,
  `DocumentSession.swift` (repair only if the journey fails), shell-tabs/voicegroup
  fixtures. Lanes: swiftcore, `--filter bankleases`, shell-tabs, shell-voicegroup.
  After 36 (shell composition collision).
- **task-38 — session-owned time selection + time/ruler menu semantics**
  Outcome: roll-level time selection (fork `EditorSelectionModel` semantics) drives menu
  enablement, paste rejection and scope gestures; stale/cancel/no-write, two-step undo,
  insert-time no-op proven; includes task-35's deferred ruler-sweep/right-click timing
  follow-up. Fork: `editorselectionmodel.h:23-76`, `timemenu.cpp:101-137`. Current:
  `ApplicationSession.swift:525,1063,1362-1391` derives from the automation page;
  `RulerMenuPresenter.swift:81-176` menus exist. Ledgers: timemenu 69+6,
  ruler_loop_menu 60+13, clipboard selectioncheck_tracks preamble. Write-set:
  `PianoGrid.swift`*, `EditorSurface.qml`*, `RulerMenuPresenter.swift`,
  `ApplicationSession.swift`*. Lanes: shell-grid-menu, shell-clipboard, swiftcore,
  verify:qml-roll. After 36 + 37.
- **task-39 — ED09-2 Event List edit slices + row-menu canonicalization** *(ready)*
  Outcome: `rawTempoAtomic` coherence, same-tick reorder/drag bounds, delete matrix,
  drawer-focus Delete routing (task-19 deferrals, `proof.edits.txt` 74 rows); plus the
  row-menu authority repair: canonical Move Event Up/Down through
  `session.performEventListCommand` (today `EventListMenus.swift:148-154` calls
  `moveRawEvent` directly), conditional Show-voice-in-voicegroup for Program Change, and
  the dynamic `Delete %n event(s)` count (fork `eventlistcontroller.cpp:1060-1108`).
  Write-set: `src/swift/app/eventlist/*`, `EventListPage.qml`. Lanes: shell-event-list,
  swiftcore. Parallel with 37/38.
- **task-40 — ED10-2 pitch-bend anchoring/lifetime + external-edit preview** *(ready)*
  Outcome: popup anchored to the selected note within window bounds (fork G-key law,
  `pitchbend/lifecycle.cpp:56-75`), owner lifetime, external-edit preview refresh.
  Ledgers: curve A058–A087 + lifecycle rows. Current: `PitchBendPopup.qml`,
  `src/swift/app/pitchbend/*`. Lanes: shell-pitch-bend, verify:qml-roll. Parallel.
- **task-41 — ED10-3 pitch-bend mod-wheel/reset + snapping + controller scrub**
  Outcome: mod-wheel/reset laws (A088–A096, A115–A123), Alt/fine-grid/signature-boundary
  snapping (A097–A114), controller-lane wheel scrub writing note-bounded CC14/CC15
  (`pitchbend/controller.cpp:39-110`). Ledgers: curve remainder, controller 80+1, vertex
  36, raster 22. Write-set: `pitchbend/*`, `PitchBendPopup.qml`. Lanes:
  shell-pitch-bend. After 40.
- **task-42 — ED05-2 scale-aware editing**
  Outcome: fold keyboard nudges, multi-note mapping, off-scale degree vs octave motion,
  per-tab scale state proof. Ledgers: scale_editing 31+4, scale_projection 15+9,
  scale_fold 11+2, tabs_scale 38 (re-verify; selector text stale). Fork oracle:
  `src/checks/rollcheck/scale_editing.cpp`. Current: `ScaleProjection.swift`, selector
  at `TransportBar.qml:231-313`. Write-set: `PianoGrid.swift`*, `ScaleProjection.swift`.
  Lanes: verify:qml-roll, swiftcore, shell-transport. After 38.
- **task-43 — AU04 Polyphony Debugger gesture/flash parity + proof** *(ready)*
  Outcome: repair the two visible mismatches — event rows must require **double-click**
  to jump (fork `polyphonypanel.cpp:~360-370` `itemDoubleClicked`; current
  `PolyphonyPanel.qml:285-310` single-click `TapHandler`) — and the counter flash must
  be the fork's ~1s **alpha fade** (`polyphonypanel.cpp:598-620`; current binary flash
  colors `PolyphonyPanel.qml:213-240`); then counters/reset, hide-show inversion
  suspension, session-only inversion, audition exemption, 500-row cap,
  positioned-vs-live jump split (`PolyphonyPanelPresenter.swift:199-203` already
  correct). Fork: `src/ui/polyphonypanel.h:19-40`, `docsrc/manual/polyphony.md`.
  Ledgers: polyphonypanel 30+2 (A012–A018 GAP, A019 PARTIAL), polyphonygate 14+1.
  Write-set: `PolyphonyPanel.qml`, `PolyphonyPanelPresenter.swift`,
  `tst_ShellPolyphony.qml`; dock mount is in task-36-hot `ShellWindow.qml:523-577`.
  Lanes: shell-polyphony, swiftcore audio. Slot after 36.
- **task-44 — SH06 preference remainder (fork keys Swift does not own)**
  Outcome: own and persist `followPlayhead` and `dsp.resonanceSuppression` (currently
  setter-only, `TransportBarPresenter.swift:174-185`; task 36 deliberately leaves these
  legacy keys untouched — this is the follow-on ownership decision); restore/write
  `windowGeometry`/`windowState` and `songFilterText/Sort/Category` (fork
  `mainwindow.cpp:162-168,425-431,465-480`; no Swift path exists); check the output
  dial's incremental global-Y drag law (fork `transportbar.cpp:38-70`; current
  `TransportOutputDial.qml` computes from press origin); also verify Follow-Playhead
  menu enablement (fork keeps it checkable and enabled without a song,
  `transportbar.cpp:297-304`; Swift disables it, `ShellPresenter.swift:226-227`).
  Engine/Song settings pages are substantially present — prove, don't rebuild.
  Write-set: `ShellWindow.qml`*, `ShellPresenter.swift`, `TransportBarPresenter.swift`,
  `SongListPresenter.swift`, `ApplicationSession.swift`*. Lanes: shell-transport,
  shell-songs, shell-window, swiftcore. After 36 (highest collision) + 37.
- **task-45 — SH02 velocity-color/note-name rasters**
  Outcome: fork velocity color ramp + note-name/value raster laws in roll rendering.
  Fork: `SongView::noteColor`/`velocityNoteColor` (`songview.h:337`,
  `trackvoiceops.cpp:175`). Current: GridPalette identity `noteFill` (ledger reason in
  `proof.note_rendering.txt`). Ledgers: velocityColorRaster 11, noteNameRaster 11,
  velocityValueRaster 8. Write-set: `GridPalette.swift`, `GridScene.swift`. Lanes:
  shell-note-visuals, verify:qml-roll. Parallel.
- **task-46 — SH01 menu topology & context-menu shape**
  Outcome: fork menu structure — Find Song under Edit (not File), Transport as Edit >
  Transport (not top-level), fork Edit submenu grouping (Time/Notes/Move/Tracks/
  Automation/Events/Loop/Transport, `mainwindow.cpp:75-135`); expose the registered
  loop actions `edit.set_loop_start`/`set_loop_end`/`remove_loop`
  (`KeybindingRegistry.swift:124-127` already defines them); note-context rows become
  fork-shaped (Set Velocity…, no Paste, fork order/separator, `pianoroll_commands.cpp:538-578`;
  current `ShellPresenter.swift:109-112` is Copy/Cut/Duplicate/Paste/Delete/Split/Join);
  shortcut-text projection for action-backed custom rows (`RulerMenuPresenter.swift:7-25`
  has no shortcut field); label normalization to fork wording (Copy Selection vs Copy
  Notes etc.). Deferred rows (New Song/Import MIDI/Export WAV/Import Sample/Theme) stay
  absent; `transport.resonance` menu placement is checked against the fork transport bar
  (fork keeps it a bar control, not a menu row). Write-set: `ShellPresenter.swift`*,
  `ShellWindow.qml`*. Lanes: shell-menus, shell-grid-menu, verify:bridge. After 36 + 44.
- **task-47 — ED07 automation point-menu remainder**
  Outcome: second-track fixture (A041/A047-49), cross-surface invalidation
  (A073/74/81/87-89), raster lane A096, two-point CC fixture (A216/219/220). Ledgers:
  automationpointmenus 28+16 left. Write-set: `src/swift/app/drawer/automation/*`.
  Lanes: verify:qml, swiftcore. Parallel.
- **task-48 — ED03 track-header budget styling + surface proof**
  Outcome: tracks over the song's voice/player budget get the fork's dimmed
  title/subtitle styling (fork `trackheadermodel.cpp:241-258`; no budget comparison in
  `TrackHeadersGeometry.swift:220-280` — clearest ED03 omission); then
  converted-window proof for activity meter geometry/DPR, role/dataChanged and all five
  context-menu actions incl. disabled duplicate and outside dismissal (already
  fork-shaped: `TrackHeaders.swift:417-423`). Ledgers: activitymeter 16+27, menu 23+10,
  mutations 17+34. Write-set: `TrackHeadersGeometry.swift`, `TrackHeaders.swift`,
  `TrackHeaderBand.qml`. Lanes: verify:qml-roll, swiftcore. Styling slice parallel;
  menu/fixture proof after 36 (`EditorSurface.qml` mount).
- **task-49 — ED11 clipboard track interoperability**
  Outcome: track-scoped copy/paste/remap precedence once time selection exists
  (task-38). Ledgers: selectioncheck_tracks 80+14, clipcheck_copy 23+8, merge 8+4.
  Write-set: `Clipboard`/`EditCommands.swift`. Lanes: shell-clipboard, swiftcore.
  After 38.
- **task-50 — ED12 window-tier keyboard precedence slice**
  Outcome: window-tier shortcut precedence, popup arbitration, every cancellation cause.
  Ledgers: selectionkey windowtier_keyboard 70+13, localinputtier_text 36 PARTIAL.
  Write-set: `KeybindingRegistry.swift`, `ShellWindow.qml`*. Lanes: shell-menus,
  shell-grid-input, swiftcore. After 44/46.

Following-sprint backlog (authorized, not queued above): VG01/VG02 editor
presentation/picker obligations (voicegroupsave presentation 80, picker 41+3), ED06
drawer-velocity real-delegate/zoom PARTIAL upgrades, PJ05 ordered-save predicates,
mainwindowrouting/eventviews.chrome/timelinepan mapping debt, P8 native-host lanes.

## 6. Sequencing and parallelism

Chain A (session/roll hot files): 36 → 37 → 38 → {42, 49}. Chain B (shell chrome):
36 → 44 → 46 → 50. Pitch-bend chain: 40 → 41. Free-parallel at any point: 39, 43 (slot
after 36), 45, 47, 48-styling. Recommended dispatch order: 37 immediately after 36
settles; then 39 + 40 + 43 in parallel; then 38; then 44/45/47; then 41/42/46/48/49;
50 last. Each brief re-verifies its ledger rows against current source at freeze
(preamble text is known-stale in pitchbend/tabs_scale/polyphony).

## 7. Assumptions

- Task 36 lands as briefed; tasks 44/46/50 depend on its PreferencesStore and freed hot
  files. If 36 stalls, 37–41/43/45/47–49 still dispatch unchanged.
- "Existing-surface parity" remains the authorized scope; nothing in section 4 is
  authorized by this document, including the Register Song wiring question.
- VG05's repair approach (invalidation vs adoption) stays inside the one-history-authority
  constraint; task-37 fixes the outcome, not the mechanism.
- Census counts are GAP+PARTIAL on the assessment tree; rows move as task 36's ledger
  pass lands. ForkMenus/ForkSurfaces findings are read-only source comparisons, not
  executed checks — briefs re-verify at freeze.
