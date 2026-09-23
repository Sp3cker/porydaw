# task-6-brief.md — Voicegroup list panel and QML integration

## Context

The Swift list model already exists as
`src/swift/app/voicelist/VoiceListController.swift`; Task 6 integrates that
controller into the song-tab workspace and QML shell. It is not a new
`VoicegroupPresenter`. The model already owns the stable 128 rows,
`setVoicegroupChoices`, `setCurrentVoicegroupArg`, `revealSlot`,
`pressVoice`/`releaseVoice`, and `onVoiceEditRequested(slot,voice,structural)`.
Its existing row derivation uses parsed `BankVoice` data and the native
`BankSlotView.tone` fallback (`ProjectService.swift:99-145`,
`VoiceListController.swift:483-538`); preserve both paths.

Native parity references are `VoicegroupBrowser` row/selector construction
and rendering (`src/ui/voicegroupbrowser.cpp:64-133,231-330,564-620,730-737`)
and `WorkspaceUi::rebuildVoicegroupPresentation`
(`src/ui/workspaceui_voicegroup.cpp:180-216`). The workspace and selected
tab already carry the reveal signal:
`ApplicationSession.revealTrackVoiceRequested(track:)`,
`DocumentWorkspace.Callbacks.revealTrackVoiceRequested`, and
`TrackHeadersPresenter.onRevealTrackVoiceRequested`.

## Exact write set

- `src/swift/app/DocumentWorkspace.swift` — own/bind the existing
  `VoiceListController`, refresh it from session changes, route audition,
  selector commit, and active-bank audio rebind.
- `src/swift/app/SongTabsController.swift` — expose
  `SongTabSession.voiceListController()`.
- `src/swift/app/ApplicationSession.swift` — fetch and retain the
  project-scoped catalog plus existing selector args; add
  `refreshVoicegroupData()` for project mutations.
- `src/swift/app/voicelist/VoiceListController.swift` — add
  `revealTrack(track:)` using its bound session and shared playhead.
- `src/swift/app/timeline/GridPalette.swift` and
  `src/app/RewriteWindow.cpp` — add/push the existing-browser-equivalent
  `usedVoiceTint` palette role; restore/persist `swiftDock/songsRatio` and
  apply the split's parent minimum height.
- `src/app/voicetypeiconprovider.h` and
  `src/app/voicetypeiconprovider.cpp` — new QML image provider using the
  existing icon table.
- `src/ui/voicetypeicons.h` and `src/ui/voicetypeicons.cpp` — register the
  existing source in app and native-check builds; do not fork its mapping.
- `src/ui/songview/quick/swiftroll/SongsPanel.qml` — expose the controls-plus-
  one-row minimum height required by the second dock pane.
- `src/ui/songview/quick/swiftroll/VoicegroupPanel.qml` — new functional
  selector/list component and its controls-plus-one-row minimum height.
- `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml` — mount both panels
  in Task 3's dock column and add the persisted vertical split.
- `CMakeLists.txt` and `src/checks/CMakeLists.txt` — register the QML,
  provider/icon sources and the seven `/icons` SVG resources in the app
  and native-check engines.
- `src/checks/voicelist/voicelist_session.swift` — add the effective
  track-to-voice reveal scenario.
- `src/checks/swiftrollgated/voicegroupchecks.cpp` and
  `src/checks/swiftrollgated/tst_swiftrollgated.h` — native shell checks.
- `src/checks/swiftrollgated/nativefixture.h` — isolate QSettings, open a
  copied `ProjectFixture`, and assert the native app/audio/song readiness
  needed by each panel scenario.

## Prerequisites

Tasks 2 and 3 must finish their `ApplicationSession.swift`, `SongsPanel.qml`,
`SwiftRollOverlay.qml`, and shell ownership first. Task 6 is the first writer
of `DocumentWorkspace.swift` and owns adding/binding `VoiceListController`
there. Task 4 must finish its shared `GridPalette.swift` and
`RewriteWindow.cpp` palette work before Task 6 adds `usedVoiceTint` and the
ratio persistence there. Task 5 supplies the catalog, sample data, and
`setVoicegroupArgument(_:)`. Task 3 owns the horizontal `columnWidth`
splitter/persistence; Task 6 adds the independent vertical splitter and
`swiftDock/songsRatio`. Serialize edits at each shared-file boundary. Tasks
7-10 consume this controller/panel. Task 9 wires the existing
`onNewVoicegroupRequested` intent and creation affordance; Task 10 wires the
existing sample mutation intents. Neither mutation flow is implemented in
Task 6.

## Interface contract

Spec section 4.6. Exact behavior:

- **One controller per document** — `DocumentWorkspace` constructs and binds
  the existing `VoiceListController`; `SongTabSession.voiceListController()`
  returns that tab's instance. Rows remain the controller's stable 128-row
  model. Do not create a parallel presenter or copy bank state.
- **Rows and icons** — keep `BankVoice` authoritative for parsed editable
  slots. For read-only, broken, or otherwise unparsed nonblank slots, keep
  using `BankSlotView.tone.name`, raw `type`, `isSynth`, and optional ADSR;
  do not replace the real tone with a placeholder. Preserve blank-row text,
  type names, ADSR masking, alt-chip semantics, and icon keys from
  `VoiceListSemantics` / `voicetypeicons::iconKey`. Use the seven existing
  SVGs (`waveform.svg`, `wave-square.svg`, `wave-triangle.svg`,
  `wave-sine.svg`, `waveform-path.svg`, `piano-keyboard.svg`, `drum.svg`)
  under `/icons`; the provider renders the canonical tint/rotation from
  `voicetypeicons::kIconSpecs`. Make the QML image URL change with the
  palette text role so theme changes request a freshly tinted image.
- **Used rows** — preserve `refreshUsedVoices(from:)`: include
  `firstProgram` only for used tracks and every voice-lane point across the
  document. Refresh the marks with document/bank changes and tint them with
  `usedVoiceTint` at the native `markUsedRow` accent alpha.
- **Selector and catalog lifetime** — fetch `voicegroupCatalog()` and the
  existing `voicegroupArgs()` separately; replace the project snapshot only
  when both succeed for the current project. Fan the successful snapshot to
  every workspace. `refreshVoicegroupData()` keeps the last successful
  same-project catalog/args on outage, reports the service error through
  the existing operation-failure status path, and never leaks a previous
  project's catalog into a newly opened project. Task 9/10 call this method
  after successful catalog mutations. The selector uses
  `VoiceListSemantics.voicegroupDisplayName` and
  `voicegroupArg(fromDisplay:knownArgs:)`; empty and `"_dummy"` fold to
  the same current choice. Commit on activation and editor finish/focus loss
  through `session.setVoicegroupArgument`. While the request is in flight,
  loading disables the selector and keeps row geometry/selection stable; a
  failed rebind keeps the previous bank rows and reports the error.
- **Audio and reveal** — route controller audition to
  `NativeAudio.previewVoice(program:key:velocity:)`, with velocity `0` on
  release. On an active workspace's `.bank` publication call
  `audio.updateVoicegroup(session.bankLease)`; catch and surface errors
  through `publicationFailed`, never `try?` them away. Hidden tabs rebind
  when activated. `revealTrack(track:)` uses the same
  `VoiceLanePolicy.slot(firstProgram:tick:points:)` rule as
  `TrackHeadersGeometry.makeSnapshot` (`playing ? playhead.tick :
  session.editCursor`), then calls `revealSlot`. The shell connects the
  existing header signal to the selected page's
  `voiceListController().revealTrack(track:)`; reveal scrolls/selects but
  never takes keyboard focus.
- **QML and dock geometry** — expose the panel's `vgArgCombo`, `selector`,
  `tree`, `tree.header`, `tree.row.NNN`, `.type-icon`, and `.adsr` object names
  for native inspection. Row press/release/cancel uses controller
  `pressVoice`/`releaseVoice`. Mount SongsPanel above VoicegroupPanel in one
  Qt Quick `SplitView` inside Task 3's dock column, with
  `orientation: Qt.Vertical`, object name `voicegroupDockSplit`, and a
  horizontal draggable handle named `voicegroupDockSplitHandle`. Give the
  pane roots object names `songsPanelDockPane` and
  `voicegroupPanelDockPane`.
  `songsRatio` is the normalized Songs-pane height over split content height
  excluding the handle; default to `0.5`, restore it from and persist it to
  `swiftDock/songsRatio`. Clamp the restored/dragged ratio so each pane keeps
  its controls plus at least one list row. Expose `minimumPaneHeight` on both
  panel roots: SongsPanel's value is its search/category/sort/count controls
  plus one row; VoicegroupPanel's is its selector/header plus one row. Set
  the parent column/window minimum height to the sum of those minima and the
  handle; window resizing preserves the ratio unless minima clamp it. The
  panes never overlap or collapse. Persist only user divider moves, not
  initial layout/restoration. Keep Task 3's horizontal `columnWidth` range
  and persistence separate.
  Do not discard or recompute the third `structural` argument on
  `onVoiceEditRequested`; Task 7 consumes that existing edit intent.

## Implementation steps

1. Add the per-tab controller to `DocumentWorkspace`, pass it the shared
   playhead, bind/refresh on document and bank publications, expose it from
   `SongTabSession`, and rebind active audio with surfaced errors.
2. Add project-scoped catalog/selector state and
   `refreshVoicegroupData()` to `ApplicationSession`. On project replacement
   load catalog and args as a pair; on a successful refresh update all open
   workspaces, and on failure keep the same project's last valid pair.
3. Implement `VoiceListController.revealTrack(track:)` with the shared
   playhead/edit-cursor rule and existing `revealSlot`; add a focused
   `voicelist_session.swift` assertion for lane-point resolution.
4. Add `usedVoiceTint` to `GridPalette` and push it through
   `RewriteWindow.applyGridPalette`. Register the canonical icon provider
   before QML creation, reuse `voicetypeicons` and its SVG resources in both
   app and native-check engines.
5. Extend `SongsPanel.qml` with `minimumPaneHeight` for its filter/count
   controls plus one list row. Build `VoicegroupPanel.qml` over the
   controller's rows, selector, loading state, icon key, ADSR, used mark,
   reveal, and press/release APIs; expose its controls/header plus one-row
   `minimumPaneHeight`. Mount it below SongsPanel in one vertical `SplitView`,
   initialize `songsRatio` to `0.5`, restore/persist it under
   `swiftDock/songsRatio`, and clamp both panes to their minima. Propagate the
   sum of both minima and handle height to the parent column/window minimum
   so neither panel collapses or overlaps.
6. Strengthen `NativeScene` in `nativefixture.h`; keep the old
   `proof.fixture.txt` A001-A004 obligations as explicit, named setup
   predicates, not product-coverage claims:
   - A001 `isolatedFixtureSettingsAreResolved`: require a valid private
     `QTemporaryDir`, point both user-scope QSettings formats at it, and
     verify the settings file resolves there;
   - A002 `copiedFixtureProjectOpens`: require `ProjectFixture::copyOf` to
     succeed and open that copied root, not the supplied source project;
   - A003 `fixtureAudioEnginePlayPauseRoundTrips`: after binding, invoke
     `ApplicationSession.playPause()`, observe the real
     `SharedPlayheadPresenter.playing` transition, then stop and observe it
     return to false;
   - A004 `fixtureSongTimelineIsOpenAndReady`: require
     `ApplicationSession.songOpen`, selected `gridModel`, and the mounted
     `sharedPlayhead` presenter to report an attached timeline before a
     panel scenario uses the scene.
   Emit a distinct diagnostic for each failed named predicate. Run the four
   panel scenarios below against this verified `NativeScene`; the split
   persistence scenario uses its own host-backed fixture.
   - `voicegroupPanelSelectedTabAndHeaderReveal`: selected-tab rows switch
     with the tab; a header request resolves the effective voice-lane slot,
     scrolls/selects it, and leaves keyboard focus on the existing surface.
     Preserve proof identity
     `vgsavecheck/VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks`;
   - `voicegroupPanelPressReleaseAndSpacePriority`: row press and release
     reach the actual audition path, stop on release/cancel, and do not
     consume transport Space;
   - `quickHeaderPressSurvivesVoicegroupRebuild`: focus the editable
     selector with a valid new arg, then press a track header so focus loss
     commits `-G`; retain the live Quick surface/header model/input through
     async rebind and panel refresh, deliver the in-flight release, verify a
     second header press still works, then undo and verify the home binding
     is restored. Keep the old proof identity
     `vgsavecheck/VoicegroupSaveTest::quickHeaderPressSurvivesVoicegroupRebuild`;
   - `voicegroupCatalogOutageRetainsLastValid`: make the staged catalog
     unavailable, verify the visible list/selector keep their last successful
     same-project values and the error is surfaced, then restore the catalog
     and verify refresh replaces them. Use proof identity
     `vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid`.
7. Add `voicegroupPanelVerticalSplitResizesAndRestores` using the production
   `RewriteWindow` through existing `tabcheck::TabScene`. Before constructing
   it, point both user-scope QSettings formats at a private `QTemporaryDir`.
   With no saved `swiftDock/songsRatio`, assert the initial ratio is `0.5`
   and matches Songs-pane height divided by split content height; initial
   layout must not create the setting. Drag toward each clamp and assert both
   actual pane heights stay at or above their computed `minimumPaneHeight`,
   each shows its controls and one row, the parent minimum is at least both
   minima plus handle height, and the panes do not overlap. Verify a divider
   drag writes the normalized ratio to QSettings. Close the window and reopen
   the session with the same settings directory; assert the stored ratio and
   pane geometry restore from `swiftDock/songsRatio`.

## Acceptance predicate

- `deno task build:app` and `deno task build:checks` succeed.
- `deno task verify --filter swiftcore --verbose` passes the effective
  track-reveal scenario and the existing VoiceList row, fallback, selector,
  and used-mark scenarios.
- `deno task verify --filter swiftrollgated --verbose` passes the four
  named `NativeScene` panel/reveal/audition/rebuild/outage scenarios with
  named A001-A004 setup predicates, plus
  `voicegroupPanelVerticalSplitResizesAndRestores` with drag/clamp,
  non-overlap, pane-usability, and ratio-reopen assertions under the desktop
  `WindowSystem`.
- The final integrated validation owner runs these gates once after all
  task edits settle. Task 6 owns no full `voicegroupbrowser` visual pin;
  Task 10 owns its exact vanilla/dark pin.

## Task-specific constraints

- Use the existing `VoiceListController` and its `BankSlotView.tone`
  fallback. Do not add `VoicegroupPresenter`, `VoiceRow`, placeholder tone
  names, duplicate bank storage, or a second selector source.
- Do not implement the editor, picker audition, new voicegroup dialog, or
  new/edit sample flows here. Keep the existing outward intents as the
  seams: Task 7 consumes `onVoiceEditRequested`, Task 9 wires
  `onNewVoicegroupRequested` and its creation affordance, and Task 10 wires
  the sample mutation intents/buttons. Do not expose a no-op control.
- Read catalog and selector values only through the compiled
  `ProjectService` bridge. Keep this task's CMake edits limited to the
  panel/icon/provider sources and resources listed above; do not reach through
  to `ProjectWorkspace`, `ProjectIo` command inputs, or uncompiled sample-
  import/DSP modules. Tasks 9/10 own the corresponding mutations; Task 11
  owns any required linking of those uncompiled modules.
- Keep Task 7/8 scenario-scoped pins separate from Task 10's full
  `voicegroupbrowser` vanilla/dark pin. Do not edit proof ledgers, frozen
  fixtures, unrelated C++ widgets/checks, or other task briefs.
