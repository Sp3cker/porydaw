# Context

Task 62 — VG01/VG02 editor presentation + picker journeys on the mounted voicegroup
dock. Close 211 open rows across four ledgers (presentation 80, editor 28, viewcache
59, picker 44), prove them on the mounted dock and presenter surfaces, and delete the
two fully closable ledgers. One production gap exists at freeze (track-header reveal
is unwired); everything else is proof completion plus small parity additions.

1. **Census (verified this freeze)**: `proof.presentation.txt` 80 GAP — its
   header (`Swift counterpart: none identified`) and command are **stale**
   (counterparts execute in `tst_ShellVoicegroup.qml`, lane `shell-voicegroup`,
   and `voicelist_session.swift`, suite `swiftcore-projectsession`).
   `proof.editor.txt` 26 GAP + 2 PARTIAL (A006/A008 cite S001–S007; unproved:
   engine release parity) + 4 RETIRED. `src/checks/voicegroup/
   proof.tst_voicegroupviewcache.txt` 56 GAP + 3 PARTIAL (A023/A036/A069) + 8
   MATCHED (S001–S012) + 3 RETIRED (A041/A044/A070 cache/lease identity).
   `proof.picker.txt` 41 GAP + 3 PARTIAL (A017/A020/A035) + 3 MATCHED.
2. **Fork laws** (`git show <pinned>:…`; presentation pins 4346c26a — fceecd88
   adds one line there, `iconSize().height() >= layout::fontPx(1.5)` in
   `typeColumnMapsEveryFamily`; editor f31a88ba and picker/viewcache a7fcaa3e are
   byte-identical to fceecd88). Clause detail lives in the ledger mapping below;
   the laws, per file:
   - `voicegroupsave/presentation.cpp` — `revealsTrackProgramsAndUsedMarks`
     (:64-89) used marks vs `usedVoices()`, dock reveal (`revealTrackVoice`/
     `revealVoice`), voice-lane mark + undo; `quickHeaderPressSurvivesVoicegroup-
     Rebuild` (:95-170) alternate `-G` typed mid-press, press/binding/undo
     outcomes (:139-:166; QPointer rows :137-162 pin Quick-view rebuild
     mechanics); `newVoicegroupCreatesAndAssignsUndoably` (:239-256) — **VG03,
     not this task** (inventory.md VG03 Missing; `onNewVoicegroupRequested`
     :148 fires from `requestNewVoicegroup()` :545, assigned by nobody);
     `typeColumnMapsEveryFamily` (:265-422) — Type column sizing (iconSize ≥
     `fontPx(1.5)`, width ≥ icon + 2·`space(Two)`), slots 0–12 family table
     (:280-293: Sample, fixed-pitch, reverse, Square 1/2, Wave, Noise, Keysplit
     ×2, Drumkit ×2, cry-as-Sample), tooltip = accessible text = family name,
     icon-only column, typeless blanks, 8 pairwise-distinct glyphs, cry shares
     sample glyph, synth staging → memory-only tone + "Synth (Golden Sun)"
     text/accessible/glyph, fixture_alt "… (Alt)" names on grey chips, alt blanks
     typeless.
   - `voicegroupsave/editor.cpp` — `releaseEditorUsesBankUndoPipeline` (:36-77)
     spin/drag release edit → bank worker, drag keeps field unfocused and dock
     minimum size unchanged, bank-pipeline commit, undo restores release + engine
     with clean document; `blankTemplateMaterializesUndoably` (:81-126) `"%1
     [Blank]"` row, notice-free blank with DirectSound default and equal sample
     buttons, Square1 materialization (bank dirty, document clean, engine
     SQUARE_1), undo/redo/settle; `dockMinimumWidthIsFamilyInvariant` (:136-145);
     `adsrFieldSpaceTogglesTransport` (:154-172) Space → play/pause once, text and
     focus preserved.
   - `voicegroupsave/picker.cpp` — `samplePickerAuditionsAndCommits` (:41-124)
     picker button replaces combo, popup outline/rows/loop badge, filter →
     audition + shared sample set, first click previews / second commits+closes+
     stops, clean document + dirty bank, undo, unlisted-symbol Return commit;
     `samplePickerKeysplitAuditions` (:130-143) keysplit-kind audition;
     `samplePickerWaveModeAuditionsAndCommits` (:149-205) ProgWave mode, wave-only
     list with full symbols, wave-kind audition, Return commit, two-step undo.
   - `voicegroup/tst_voicegroupviewcache.cpp` (pure presenter laws over a
     FakeBank double) — `historyLifecycleAndStaleTransitions` (:126-208)
     document/bank undo-redo ordering, one-step bank edits, blank-slot
     materialization token + revert + fresh-token redo, stale conflicts prune one
     command; `mergeRules` (:211-253) merge/self-cancel/nonmergeable/markSaved/
     seal; `coordinatorRoutesTransitionsAndGates` (:262-325) session gate,
     transition application and index moves, conflict pruning, hard error.
3. **Swift current state**: the dock is mounted and largely complete:
   `SongsDockColumn.qml` `voiceWrap` → `VoicegroupPanel.qml` (`voicegroupPanel`,
   `vgArgCombo`, `voicegroupTree`, `voicegroupRows`, delegates `voicegroupRow_<slot>`
   with the `used` tint, icon tooltip = typeName, reverse glyph rotated 180°) →
   `VoiceEditor.qml` (typed fields incl. `vg{Attack,Decay,Sustain,Release}Spin`,
   `vgTypeCombo`, `vgSymbolPicker`, equal-size sample buttons, `vgSaveButton`) and
   `SamplePicker.qml` (`vgSamplePickerButton/Popup/Search/List/Detail/Loop`; border
   already `colors.outline` at :107; categories, typed fallback,
   audition-on-highlight, two-click commit, Escape/outside dismissal, stop-on-close).
   `VoiceListController.swift` publishes the check-relevant surface: `currentSlot`,
   `soundingVoice`, `bankDirty`, `slotIsMarkedUsed`, `selectSlot`, `revealSlot`
   (bumps `revealRequest`/`revealSlotId`; panel scrolls at :214),
   `requestSampleAudition(symbol:)` (derives kind `.wave`/`.keysplit`/`.sample` +
   family-masked ADSR, :443-458), `stopSampleAudition`, `applyVoiceEdit` (via
   `DocumentSession.applyBankEdit`), `commitVoicegroupSelection`,
   `pickerSampleDetail/Loop`, per-category symbol lists.
   `ApplicationSession.swift:148-190` wires event-list reveal, `-G` change
   (`selectVoicegroup`) and sample audition (`ProjectService.pickerSound`).
   `app.documentDirty` (:21, set at :1347 from `document.isDirty || bankDirty`) is
   the save-needed signal — song-document cleanliness is asserted presenter-level
   on `session.document.isDirty`. **Production gap (only one at freeze)**:
   `TrackHeadersPresenter.onRevealTrackVoiceRequested` (`TrackHeaders.swift:64`,
   fired by header double-click `TrackHeadersInput.swift:145` and context-menu
   action 2 `TrackHeaders.swift:358`) is attached by nobody in production — the
   track→program reveal ingress is missing. Secondary parity gap: the type icon
   has a tooltip but no `Accessible.name`. Engine-parity proof patterns exist in
   `bank_sharing.swift` (`bankBackgroundEditReachesSelectedAudio`,
   `mountedEditReachesPeerTabAudio`) — extend with release-byte asserts.
4. **Lane mechanics**: `shell-voicegroup` (`ShellQmlTests.swift:99`) runs
   `tst_ShellVoicegroup.qml` over `mus_route101`, `mus_route102`,
   `asm/macros/synth_test.inc`, `data/sound_data.s` plus the default rich fixtures
   (:48-52) — **`fixture_alt.inc` is not staged there** (only shell-songs stages
   it, :91; it exists in the catalog, `fixturecatalog.cpp:58`) — add it.
   `voicelist_session.swift` rides `swiftcore-projectsession`
   (`SessionChecks.swift:37`); viewcache predicates ride `swiftcore-bankhistory`
   (`checkcatalog.cpp:126`; `runBankHistorySuite` `SessionChecks.swift:96`,
   `bankCoordinatorGate` `bank_sharing.swift:633`).

# Exact write set

- `src/swift/app/voicelist/VoiceListController.swift` — add
  `revealTrackVoice(track:session:)` (resolve `session.timeline.tracks[track].
  firstProgram`, falling back to the track's first voice-lane point, then
  `revealSlot`).
- `src/swift/app/DocumentWorkspace.swift`* (hot) — add
  `revealTrackVoiceRequested: (Int) -> Void` to the `callbacks` struct; attach as
  `headers.onRevealTrackVoiceRequested = callbacks.revealTrackVoiceRequested`
  beside the `changeTrackVoiceRequested` line (:120).
- `src/swift/app/ApplicationSession.swift`* (hot) — one closure in `makeCallbacks`
  calling `voiceList.revealTrackVoice(track:session:)`.
- `src/ui/songview/quick/docks/VoicegroupPanel.qml` — add
  `Accessible.role`/`Accessible.name` (family name, empty for blanks) to the
  type-icon cell; other edits contingent only.
- `src/ui/songview/quick/docks/VoiceEditor.qml`, `SamplePicker.qml` — contingent
  only (no law gap at freeze; fix divergences a new predicate exposes).
- `src/checks/editorqml/tst_ShellVoicegroup.qml` — new test functions per the
  contract (used marks/reveal, typed `-G` press journey, type-column families/
  blank/alt/synth, blank-template undo/redo, dock-width invariance, ADSR Space
  transport, picker journeys).
- `src/checks/editorqml/ShellQmlTests.swift` — add
  `"sound/voicegroups/fixture_alt.inc"` to the `shell-voicegroup` fixtureFiles.
- `src/checks/voicelist/voicelist_session.swift` — presenter predicates (used-set
  derivation, reveal, song-clean/bank-dirty, blank redo, audition kinds/masks,
  stop, glyph distinctness via `VoiceListSemantics.iconKey`).
- `src/checks/workspace/bank_edits.swift`, `bank_history_probes.swift`,
  `bank_sharing.swift` — viewcache lifecycle/merge/coordinator predicates and the
  release engine-parity block (patterns: `bankCoordinatorGate` :633,
  `releaseEditorBankHistorySemantics` `bank_edits.swift:287`).
- Ledgers (controller-delegated ledger agent): row flips in all four; **delete**
  `proof.editor.txt` and `proof.picker.txt` when every row is MATCHED/RETIRED;
  `proof.presentation.txt` and `proof.tst_voicegroupviewcache.txt` survive with
  named GAP deferrals (Task-specific constraints).

No CMake changes (no new files). Sizing exception: one surface family (the
voicegroup dock + its bank history contracts) over 10 files, three verification
surfaces — named for the dispatch table.

# Prerequisites

Task-54 settled (its uncommitted set owns `ApplicationSession.swift`; 59b follows
it) — the `ApplicationSession.swift`/`DocumentWorkspace.swift` edits here serialize
after 54. Task-61 landed (089652fc); its interfaces are consumed as-is. No other
task's interface is consumed.

# Interface contract

- `VoiceListController.revealTrackVoice(track: Int, session: DocumentSession)` —
  resolves the track's current program (`timeline.tracks[track].firstProgram`, else
  the track's first voice-lane point) and routes into `revealSlot(slot:)`; no-op
  for a negative or unmapped program. Pure presenter addition; no bridge surface
  changes.
- `DocumentWorkspace` callbacks field `revealTrackVoiceRequested: (Int) -> Void`
  attached to `headers.onRevealTrackVoiceRequested` exactly as
  `changeTrackVoiceRequested` is today.
- New check anchors are message-anchored, one per fork clause family; the exact
  strings appear quoted at first use in the ledger mapping below and stay verbatim
  once written. Mounted lane unless the mapping prefixes them `p:`
  (presenter-level).
- Preservation contract: every existing check message in touched files stays
  verbatim — in particular the S-cited anchors of `test_editorAndUndo`,
  `test_editorQueuedEditsKeepTheirSlot`,
  `test_zPickerAuditionsAndCommitsSampleWaveAndKeysplit` ("mounted sample picker
  exists", "popup opens after clicking button at ", "first click only auditions",
  "second click commits ", "wave macro is selected", "sample picker preserves
  grouped section headings", "sample picker offers the typed symbol fallback") and
  the voicelist/bank suite anchors cited by viewcache/editor S rows.

# Implementation steps

1. Wire the reveal ingress (three production files above), stage `fixture_alt.inc`
   for the lane, and add the type-icon `Accessible.name`. Expected GREEN against
   step 2's predicates.
2. Add the mounted predicates to `tst_ShellVoicegroup.qml`, reusing its helpers
   (`waitForNative`, `findChild` by objectName, the picker-detail wait at :323) and
   the header-press pattern of `tst_SwiftRollTrackHeaders.qml`
   (`timelineTrackHeaderRows`; the shell lane's roll mounts after song open).
   Expected GREEN — a failing predicate exposes a real divergence; fix it in the
   contingent files and record RED→GREEN for that fix only. Press-journey
   ordering: type the alternate arg into `vgArgCombo`, commit, press the second
   used track's header before the rebind settles, then assert selection and the
   settled `selectorText`/`bankLoadName`.
3. Extend `voicelist_session.swift`: attach spy closures to
   `onSampleAuditionRequested`/`onSampleAuditionStopRequested` (the production
   seams `ApplicationSession` itself uses — no test-only seams); drive
   `requestSampleAudition` for a sample, a wave and a keysplit symbol asserting
   kind and ADSR masks, then `stopSampleAudition`; add the full used-set
   derivation (programs + lane points), reveal asserts, song-clean/bank-dirty
   after edit and picker commit, and the blank-slot redo.
4. Extend the bank suite files for the viewcache rows: lifecycle/merge blocks
   against `DocumentSession` bank history (extend `historyTransitionRegressions`,
   `bankMergeSealing`, `bankConflicts`, `bankBlankMaterialization`; the
   materialization token comes from task-61's `ProjectBankEditOutcome.applied`), a
   coordinator block extending `bankCoordinatorGate` (undo/redo/initial
   transitions, conflict pruning, hard error), and the release engine-parity block
   in the `bank_sharing` audio pattern.
5. Run the lanes below; the evidence JSONs under `build/proof-evidence/` feed
   the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-voicegroup --verbose` — all new + existing
  mounted dock/picker predicates and this file's shell-lane regressions.
- `deno task verify --filter swiftcore-projectsession --verbose` — voicelist
  additions plus session-suite regressions.
- `deno task verify --filter swiftcore-bankhistory --verbose` — viewcache/bank
  predicates and regressions.
- Runtime prerequisites: macOS, offscreen-capable Qt windowing, working
  application audio (the dock binds audio on song open).

# Task-specific constraints

- Hot files: `ApplicationSession.swift`, `DocumentWorkspace.swift` (this task) —
  serialize behind task-54's settlement; `ShellWindow.qml`, `EditorSurface.qml`,
  `PianoGrid.swift`, `tst_EditorDrawer.qml` are untouched (disjoint from 54/59b/
  60). Track-header *inputs* are read-only here (double-click/menu reveal only) —
  task-66 owns header mutation proof.
- No new C++; no code comments (delete stale ones inside edited regions); no pixel
  constants in production — the type-column sizing asserts derive from base-font
  geometry (`baseFontPx`), matching the fork's `fontPx`/`space` laws.
- The song-clean invariants are presenter-level (`session.document.isDirty`),
  never `app.documentDirty` (it folds in `bankDirty`, Context ¶3).
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent. Mapping (re-verify each row against the evidence JSONs and pinned
  sources; anchor strings stay verbatim once written):
  - presentation: A001/A002/A008/A012/A016/A017/A038/A039/A042/A048/A071/A077 →
    fixture/mount guards (guard rows whose Swift guard calls `verify`/`report.fail`
    may cite that predicate); A003/A004 → "used marks match the assigned programs
    and clear on undo"; A005–A007/A009 → "revealing a track voice selects its
    program" / "revealing a voice selects its row" (A006's dock-unhide is observed
    as the persistently mounted pane holding the selection — the dock column cannot
    be hidden, `SongsDockColumn.qml:23-30`); A010/A011 → the used-marks anchor's
    edit/undo clauses; A013–A015, A018–A021, A025–A029 →
    `RETIRED-REPRESENTATION` (pin `QLineEdit`/`QQuickItem`/`QPointer` object
    lifetime across the fork's Quick-view rebuild; verify at the ledger's Reference
    revision 4346c26a); A022–A024, A030/A031 → "a typed alternate group commits
    while a header press lands" / "the next header press restores the primary
    track" / "undo restores the home voicegroup binding"; **A032–A037 stay GAP** —
    named deferral: VG03 create flow (inventory.md P5; no production ingress);
    A040/A041 → "the type column fits its header and icon at base-font sizing";
    A043–A047 → "the type column publishes family names through tooltip and
    accessible text" / "every populated family renders its glyph" plus the
    row-structure clauses; A049–A051 → "blank rows publish no type, glyph or
    accessible name"; A052–A054 → "distinct families carry distinct glyphs and cry
    shares the sample's"; A055–A060 → synth staging guards; A061–A070 → "a
    DirectSound slot offers the synth controls" / "synth activation mints a
    memory-only tone" / "the adopted synth publishes its type and sample glyph";
    A072–A076, A079/A080 → "alternate groups publish alt family names on grey
    chips". Ledger NOT deleted (VG03 rows remain).
  - editor: A003 → "a release spin edit commits through the bank pipeline"; A006/
    A008 → p: "release edits and undo reach the audio-bound voicegroup bytes"
    (closes both PARTIALs); A007/A010 → spin-display anchors; A009 → "undo
    restores the release spin and leaves the document clean"; A011–A024 → "the
    blank template materializes Square 1 undoably" + "a blank slot shows no
    notice, matching buttons and the DirectSound default" (A012/A017/A018 as
    mounted structure guards); A025/A026 → "the dock's minimum width ignores the
    selected voice's family"; A027–A032 → "Space in a focused ADSR field toggles
    transport once". Delete the ledger when all rows are MATCHED/RETIRED.
  - viewcache: A001/A033/A040 → setup guards; A002–A007 → "document and bank
    undo/redo cross the shared history in order"; A008–A016 → "a bank edit adds
    one step without touching document identity" and boundary clauses; A017–A032
    → "blank-slot undo reverts and redo rematerializes with a fresh token" /
    "stale conflicts prune exactly one command preserving identities" (A023/A036
    upgrade to MATCHED where the new predicates inspect the pruned state);
    A035/A037 → "adjacent same-slot edits merge and self-canceling pairs vanish";
    A041/A044/A070 stay RETIRED; A032/A034/A038/A039/A042/A043/A045/A066 stay
    MATCHED untouched; A048–A067 → "the session gate routes transitions and prunes
    stale conflicts" / "a hard error keeps the entry available"; **A046/A047/A068
    stay GAP** — named deferral: origin-tab close gating and pending-origin
    preservation diverge (Swift close gate is tab-dirty-based,
    `SongTabsController`; belongs to the window-state task 65); A069 stays PARTIAL
    (task-37 adjudicated, executed evidence recorded). Ledger NOT deleted.
  - picker: A001/A028/A033/A041 → guards; A003/A004 → "the sample symbol commits
    through a picker button" / "the picker shows the slot's current symbol";
    A005/A025/A042 → search-field anchors; A007 → "the popup outline uses the menu
    outline color"; A008/A009 → "the popup lists at least two symbols" / "a loop
    badge appears after the lazy sample load"; A010/A011 →
    `RETIRED-REPRESENTATION` (native screenshot helpers; the lane's own
    `grabToImage` reference capture supersedes); A013–A015 → "filtering to a
    symbol auditions it"; A016–A020 → "the first row click only auditions" /
    "the second click commits, closes and stops" (A017/A020 close with bank-slot
    asserts presenter-side); A021/A022 → "picker commits keep the song clean and
    the bank dirty"; A023/A024 → "picker undo restores the symbol and preview";
    A026/A027 → "an unlisted typed symbol commits via the fallback row"; A029–
    A032 → "a keysplit row auditions as keysplit" + p: "keysplit and wave
    auditions carry their kind and the voice envelope"; A034–A036, A038–A040 →
    "wave mode lists the catalog's waves with full symbols" (A035 closes with the
    existing "wave macro is selected" anchor plus a bank-slot assert);
    A043–A047 → "filtering a wave auditions as wave" / "Return commits the typed
    wave symbol" / "wave undo restores the wave voice and the DirectSound
    original". Delete the ledger when all rows are MATCHED/RETIRED.
- If a mounted predicate exposes a divergence the contingent-file fix cannot
  justify (behavior law, not presentation), stop and report it — do not narrow the
  predicate.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`, `deno
   task format --check`, `deno task proof check`, `deno task proof check
   --executed` (pre-deletion state shows editor and picker fully closed), then
   `deno task proof sites --area voicegroupsave` / `--area voicegroup` confirm the
   two deletions and surviving deferrals (presentation A032–A037, viewcache
   A046/A047/A068).
2. Visual/native smoke (desktop, `mus_route101`): used tints match the tracks'
   programs; double-click a track header — the dock selects and scrolls to its
   program; type the alternate `-G` and click another track mid-switch — selection
   lands, undo returns home; blank slot → Square 1 undo/redo round-trip; dock width
   stable across CGB/DS slots; Space in the release field toggles playback; picker
   filter/audition/loop badge, two-click commit with stop, Escape dismisses,
   unlisted symbol commits on Return, wave-commit undos restore both steps.
