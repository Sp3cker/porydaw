# Task 89 brief — voicegroup dock save journey: failed rebind, save receipts, synth mint, picker/editor residuals

# Context

The mounted voicegroup dock already edits, saves and switches banks (tasks
62–63, 78). This task closes the family's long tail as one coherent
edit → save → reopen/refresh journey: the failed-rebind dock UX (selector and
spin stay live, rows and binding retained), completed-save receipts and
byte-exact newer-state persistence, synth mint/save/catalog refresh,
selector/undo text, the materialized-slot engine type, and the
picker's current-symbol publication. It is not a pointer-cleanup or
catalog-outage task.

1. **Verified census: 38 selected rows of 66 open** in
   `src/checks/voicegroupsave/` (HEAD
   `e334b318ecf391e3d4fac512c4a613303aff01e3`, after task 78):
   - `proof.savecore.txt` (**14** of 29): GAP A001, A002, A007, A008, A009,
     A010, A027; PARTIAL A011, A050, A061, A062; and PARTIAL A005, A006,
     A080 → **RETIRED-REPRESENTATION**. A005/A006 compare native shared_ptr
     identity. A080 is the deleted Boolean `saveSelectedSong()` return;
     Swift `save()` returns Void, while S021 executes its zero-publication,
     unchanged-byte clean-save law. Never add a Boolean compatibility shim.
   - `proof.switching.txt` (**6**, all open rows): PARTIAL A005, A026; GAP
     A012, A016, A021, A029.
   - `proof.editor.txt` (**4**, all open rows): PARTIAL A010, A021, A023, A032.
   - `proof.picker.txt` (**4**, all open rows): PARTIAL A004, A017, A024, A038.
   - `proof.synth.txt` (**10**, all open rows): GAP A006, A008, A012, A013,
     A024, A025, A035; PARTIAL A015, A021, A040.
   - Dispositions: **35 MATCHED** and **3 RETIRED-REPRESENTATION**.
   - Not selected: savecore **A016–A026**, the catalog-outage status-path
     user decision. **A003/A004/A015** need a cohesive failed-rebind
     cfg-edit/status/undo surface: Swift currently leaves history unchanged on
     failure, so an unavailable/no-op Undo cannot prove the fork's undo journey.
     **A075** needs a deterministic mounted stale-save/retry receipt fixture;
     do not substitute timing sleeps or count a different save. These four are
     technical parity work, not newly invented user-decision blockers.
     `proof.presentation.txt` A032–A037 (VG03 New-Voicegroup create flow,
     named deferral) and A055–A059/A063/A077 (Qt file-API staging returns and
     pre-activation controls — another surface). `proof.switching.txt`
     A030–A046 are already closed by task 78's landed ruling; nothing is
     reserved there.
2. **Fork laws**, `fceecd88:src/checks/voicegroupsave/…`:
   - `savecore.cpp:43-74` (`failedRebindRetainsBinding`): the selector exists
     (`:50` → A001); activating a missing `-G` drives the load attempt
     (`:54` → A002); after the failure the dock is not loading (`:62` → A007),
     the selector stays enabled (`:63` → A008), the release spin exists and is
     enabled (`:64-65` → A009/A010), the slot row text is retained
     (`:66` → A011); undo restores the pre-failure binding and the document
     is not dirty (`:73` → A015, with A005/A006's identity halves retired).
   - `savecore.cpp:120-136` (`releaseEditDirtiesOnlyBank`): an adjacent, 0
     and 255 release edit dirties only the bank — the document stays clean
     and the window unmodified (`:124` → A027).
   - `savecore.cpp:187-196, 230-238, 273-276, 281-287`: each real save
     publishes exactly one clean receipt (A050, A061, A075), the retried
     newer-state save leaves disk bytes equal to the newer MIDI (A062), and a
     clean save is a no-op that returns false and emits no receipt (A080).
   - `switching.cpp:66-92` (`selectorSwitchUsesUndoableCfgEdit`): the
     selector's activation drives the undoable `-G` seam (`:81` → A012) and
     after undo the selector shows the home group again (`:90` → A016).
   - `switching.cpp:93-176` (`valueCommandSurvivesSourceReplacement`): after a
     value-command save, a clean `-G` round trip away and back replaces the
     home source from disk (`:127` → A021); the baseline restoration save
     settles clean (`:156` → A026); the redo-tail command reapplies to the
     refreshed canonical bytes with a dirty bank, clean document and untouched
     disk (`:168` → A029).
   - `switching.cpp:23-64` (`switchCarriesUnsavedBankEdit`): the carried edit
     replays onto the home bank and the engine voice converges to it
     (`:48` → A005's engine half; the bank half is S010).
   - `editor.cpp:78-133` (`blankTemplateMaterializesUndoably`): after
     materialization and after redo, the engine's blank-slot voice type is
     `VOICE_SQUARE_1` (`:101,122` → A021/A023; the bank/draft/document
     conjuncts are S013/S021/S022/S025).
   - `editor.cpp:148-172` (`adsrFieldSpaceTogglesTransport`): after the
     field journey, `stopPlayback()` leaves the transport Stopped
     (`:171` → A032).
   - `editor.cpp:64-76` (`releaseEditorUsesBankUndoPipeline`): after a
     focused-spin bank undo the mounted spin still displays the original
     release (`:75` → A010; the pipeline halves are S008–S010/S029).
   - `picker.cpp:44-46, 102-104, 169-171`: the picker's current symbol at open
     is the selected voice's symbol (A004) and the wave voice's symbol in the
     wave journey (A038); a first-row click auditions without committing the
     bank slot (A017, `:88`); after undo the republished current symbol is the
     original (A024, `:104`).
   - `synth.cpp:20-180` (`synthDefinitionsStayMemoryOnlyUntilSave`): staging a
     setup definition settles the catalog refresh (A006) and captures the
     definition count (A008); the mounted waveform activation to pulse lands
     (A012); each synth parameter field exists (A013) and commits a cumulative
     param-named symbol per step (A015); the saved synth file contains the
     minted symbol followed by `::` (A021); after save the definition count is
     +1 (A024) and the refreshed catalog contains the saved symbol (A025);
     the return to pulse lands after the flips (A035); the post-undo save
     settles clean (A040).
3. **Current Swift/QML state**, verified at the baseline:
   - `src/swift/app/voicelist/VoiceListController.swift:116,121` publishes
     `bankLoadName`/`selectorText`; `:280-288` shows "Loading..." only while
     loading; `:303-314` rebinds the bank view; `:365-371`
     `commitVoicegroupSelection` resolves the typed text and emits the change
     request. The mounted selector is `"vgArgCombo"`
     (`src/ui/songview/quick/docks/VoicegroupPanel.qml:38-52`).
   - `src/swift/app/DocumentSession.swift:360-386` `selectVoicegroup` throws
     on a missing bank and leaves document, lease and history untouched;
     `:400-423` `stepHistory` rebinds across undoable `-G` edits.
     `src/swift/app/ApplicationSession.swift:162-175` catches the failure into
     `lastSaveError` only — no `operationFailed(message:)`, so nothing reaches
     `ShellPresenter.statusText` (`ShellPresenter.swift:505-515`); that gap is
     exactly why A004 stays open (83 owns both files).
   - `src/checks/workspace/bank_switching.swift:7-127`
     (`bankSwitchingParity`) already covers the selector commit, carried edit,
     failed load, value undo/redo and restoring save; the new clauses extend
     it in place. It and `VoicegroupStore.swift` carry task 78's landed
     blank-token contract — preserve it; do not reintroduce token expiry.
   - `src/checks/workspace/session_save.swift:189-262`
     (`sessionSaveJourney`) persists song+bank, round-trips, counts a clean
     save's zero publications and retries from a newer state
     (`captureSave()` at `:250` gives the canonical bytes for A062).
   - `src/checks/workspace/bank_sharing.swift:390-403` shows the engine-byte
     read pattern: `bankLease.withVoices({ $0?.pointee.release })`.
     `src/swift/app/ProjectService.swift:181-192` is the `withVoices`
     boundary; `BankTone.type` (`:98-116`) documents the raw `ToneData.type`
     byte, so the blank slot's engine type (A021/A023) is readable with no
     new C++.
   - `src/checks/workspace/bank_edits.swift:55-125` owns the blank-template
     materialization journey (slot 3) where the engine-type clauses land;
     `src/checks/workspace/SessionChecks.swift:100-115` runs it under the
     bankhistory suite.
   - The mounted dock lane is `src/checks/editorqml/tst_ShellVoicegroup.qml`:
     selector failure journey `:652-675`, synth mint/save `:677-737`,
     ADSR Space `:451-492`, picker journeys `:493-650`, save button
     `"vgSaveButton"` (`:426,705`). The picker popup positions its current row
     on the draft symbol at open (`src/ui/songview/quick/docks/SamplePicker.qml:
     110-122`, `currentEntry()` `:57-61`), so A004/A038 are observable without
     production change. The release spin is `"vgReleaseSpin"`
     (`src/ui/songview/quick/docks/VoiceEditor.qml:293-303`), synth parameter
     spins `"vgSynth"+Name+"Spin"` (`:212`) and the waveform combo
     `"vgSynthWaveformCombo"`. The transport Stop control is
     `"transport.stop"` (`src/ui/shell/TransportBar.qml:114`) with
     `TransportBarPresenter.state` 1 = stopped
     (`src/swift/app/transport/TransportBarPresenter.swift:12,79`).

# Exact write set

- `src/checks/workspace/bank_switching.swift` — engine convergence of the
  carried edit (A005), clean reopen (A021), restoration-save clean-document
  half (A026), redo-tail conjuncts (A029). Preserve task 78's messages.
- `src/checks/workspace/bank_edits.swift` — blank-slot engine-type clauses
  beside the existing materialization journey (editor A021/A023) and the
  boundary-value release convergence halves of A027.
- `src/checks/workspace/session_save.swift` — byte-exact retry persistence
  (A062); retain the existing real clean-save no-publication/byte invariants.
- `src/checks/voicelist/voicelist_session.swift` — bank-slot-after-audition
  predicate (picker A017's presenter half).
- `src/checks/projectstore/ProjectStoreSaveChecks.swift` — staged-definition
  catalog settle and count (synth A006/A008), saved-symbol `::` containment
  (A021), post-save count and catalog refresh (A024/A025).
- `src/checks/editorqml/tst_ShellVoicegroup.qml` — mounted journeys: failed
  rebind dock UX (A001/A002/A007/A008/A009/A010/A011),
  release-edit dirties-only-bank with adjacent/0/255 values (A027), completed
  save receipts (A050/A061), selector activation and undo
  text (A012/A016), spin readback after undo (A010), Stop → state 1 (A032),
  picker current symbol at open/after undo (A004/A024/A038), synth controls
  and per-step symbols (A012/A013/A015/A035).
- `src/checks/voicegroupsave/proof.savecore.txt` — only the 14 selected rows.
- `src/checks/voicegroupsave/proof.switching.txt` — only the 6 selected rows.
- `src/checks/voicegroupsave/proof.editor.txt` — only the 4 selected rows.
- `src/checks/voicegroupsave/proof.picker.txt` — only the 4 selected rows.
- `src/checks/voicegroupsave/proof.synth.txt` — only the 10 selected rows.
- `src/ui/songview/quick/docks/VoicegroupPanel.qml` — selected dock-law repair only.
- `src/ui/songview/quick/docks/VoiceEditor.qml` — selected field-law repair only.
- `src/ui/songview/quick/docks/SamplePicker.qml` — selected picker-law repair only.
- `src/swift/app/voicelist/VoiceListController.swift` — selected publication repair only.
- `src/swift/app/DocumentSession.swift` — selected save/bank-law repair only.
- `src/swift/project/VoicegroupStore.swift` — selected bank-law repair only.

The six listed production owners are conditional on an executed selected-law
divergence; preserve task 78's token contract. The write set is closed.
`ApplicationSession.swift`,
`ShellPresenter.swift`, `ShellWindow.qml`, `DocumentWorkspace.swift`,
`EditorDrawer*.swift`, `tst_ShellWindow.qml`, `tst_ShellTabs.qml` and all
task-83/84 files are unchanged. No `src/project/` C++, no CMake, no new
fixtures.

# Prerequisites

Task 78's landed blank-token contract (54c7f97a) and the task-62/63 dock
surfaces. Consumes only existing interfaces: `selectVoicegroup`,
`stepHistory`, `applyBankEdit`, `bankLease.withVoices`,
`transportBarPresenter().state`, `saveInProgress`, `windowModified`, the
controller publications and mounted dock controls. No new interface dependency
on tasks 83–88; scheduled in Group B with separate file ownership.
**Rebase after 82 lands** when re-reading the `ProjectService.swift`
`withVoices`/`BankTone` boundary cited above; it is a read dependency, not a
new write-set member.

# Interface contract

- Failed-rebind UX (A001/A002/A007/A008/A009/A010/A011): after the missing-`-G`
  activation settles, `controller.isLoading == false`,
  `controller.selectorEnabled == true`, the mounted `"vgReleaseSpin"` exists
  and is enabled, and the selected slot's published row text equals its
  pre-failure text; each clause has its own message. A002 uses typed text plus
  Return to drive the real attempt; A001 uses the existing mounted selector
  journey, not a new bare-existence test. A015 stays open: do not call an
  unavailable/no-op Undo and label that failure recovery.
- A027: with the mounted spin set to an adjacent value, 0 and 255, the bank
  is dirty, the document is clean and `windowModified` stays false; the
  engine halves (bank_edits) assert `withVoices` convergence to the exact
  release byte for the boundary values.
- Receipts (A050/A061): a real dirty song+bank save, and the restoring save
  after undo, each produce one `saveInProgress` true→false cycle, no error,
  clean resources and exact expected persisted state. A spinner cycle alone
  is not a successful receipt. A062 uses the existing deterministic
  `sessionSaveJourney`: capture the newer MIDI before retrying, then compare
  disk bytes exactly with that capture. Do not add a race-driven mounted
  in-flight edit. A080 retires only the native Boolean return representation;
  the direct real Swift clean `save()` must still publish nothing, preserve
  bytes and remain clean (S021). A disabled button press is not that proof.
- Switching (A012/A016/A021/A026/A029): the mounted selector commit (typed
  text + Return) drives the undoable seam; after undo the selector text shows
  the home group again; after a value-command save, switching away and back
  rebinds the home source from disk (clean bank, saved slot values, disk
  bytes equal the saved bytes); the restoration save leaves the document
  clean too; the redo tail reapplies with a dirty bank, clean document and
  baseline disk bytes — each unproved conjunct gets its own message beside
  the existing ones, which stay verbatim.
- Engine parity (switching A005, editor A021/A023):
  `session.bankLease.withVoices` reads the engine release after the carried
  edit rebinds home, and the blank slot's raw `ToneData.type` equals the
  loader's `VOICE_SQUARE_1` constant after materialization and after redo.
  No pointer or lease identity is compared (that is the retired half).
- Editor (A010/A032): after a focused-spin bank undo the mounted
  `"vgReleaseSpin"`.`value` equals the original release; after the ADSR
  Space journey a click on `"transport.stop"` leaves
  `session.transportBarPresenter().state == 1`.
- Picker (A004/A017/A024/A038): at popup open `currentEntry().symbol` equals
  the selected voice's symbol (and the wave voice's symbol in the wave
  journey); a first-row audition leaves `session.bankSlots[slot].voice?.symbol`
  unchanged; after undo the republished current symbol (popup reopened or
  live-republished while open) is the original.
- Synth (A006/A008/A012/A013/A015/A021/A024/A025/A035/A040): the staged
  definition reaches `service.voicegroupCatalog()` on refresh; the definition
  count is captured before and is +1 after save; the saved synth file contains
  the minted symbol followed by `::`; the mounted waveform combo activation to
  pulse lands; all four parameter spins exist and each step's commit yields
  the cumulative param-named symbol on `draft.symbol`; the return-to-pulse
  after the flip/undo cycle lands; the post-undo save settles with a completed
  success cycle, clean bank and clean document.
- Existing messages — including task 78's verbatim switching messages, the
  S016/S004 failure-retention messages and every task-62/63 anchor — are
  preserved; new clauses add new literals rather than rewriting old ones.

# Implementation steps

1. Add new clause predicates before any production repair. The controller
   executes only on the settled group and records an honestly green baseline
   where behavior already holds; missing assertions are not a claimed RED.
2. Extend `bankSwitchingParity` and `sessionSaveJourney` in place with the
   unproved conjuncts; keep task 78's messages and the single-guard token
   rule untouched.
3. Add the engine-type and boundary-release convergence clauses to the
   bank_edits journeys using the existing `withVoices` borrow pattern; never
   retain the pointer past the borrow.
4. Extend the mounted `tst_ShellVoicegroup.qml` journeys: the failed-rebind
   function gains dock-state assertions; completed-save receipt journeys
   drive the real button; the ADSR function ends with the Stop
   click; the picker functions read `currentEntry()`; the synth function
   adds the pulse activation, per-step symbol checks and return-to-pulse.
5. If a mounted predicate exposes a dock defect, fix the owning dock file
   minimally (no second status surface, no new dispatcher); anything needing
   `ApplicationSession`/`ShellPresenter` stops for coordination instead of
   edit.
6. After the group settles, run the four lanes and attach only the executed
   anchors to the selected rows in the same change, via `deno task proof:edit`.

# Acceptance predicate

Controller-run on the settled built tree, separate invocations, each at most
180 s:

- `deno task verify --filter swiftcore-bankhistory --verbose` — switching
  reopen/redo-tail/engine halves and blank-slot engine type,
  boundary release convergence; `build/proof-evidence/swiftcore-bankhistory.json`.
- `deno task verify --filter swiftcore-projectsession --verbose` — byte-exact
  retry persistence, picker presenter halves and the
  existing session regressions; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify --filter projectstore-savebank --verbose` — staged/saved
  synth catalog counts, `::` containment, refresh settle;
  `build/proof-evidence/projectstore-savebank.json`.
- `deno task verify:shell --filter shell-voicegroup --verbose` — the mounted
  dock journeys listed above plus the existing dock regressions;
  `build/proof-evidence/shell-voicegroup.json`.

Suite dispatch: `SessionChecks.swift:100-115` (bankhistory), `:10-60`
(projectsession), `src/checks/checkcatalog.cpp:273` region (projectstore
entries), `src/checks/editorqml/ShellQmlTests.swift:99-101` (shell
voicegroup); evidence writing `tools/run_checks.ts:426-434`. Native audio is
not required by these lanes except the engine-byte borrows, which need no
sound device; report any host-audio limit honestly.

# Task-specific constraints

All **sprint-3 §8 Wave constraints and §9 policy** are incorporated: Swift 6.4
idioms, two-line comments, base-font geometry, WCAG AA, sole window keyboard
authority (ADSR fields yield bare Space to the window; no second dispatcher,
synthetic forwarding or focus memory), one
message-anchored predicate per fork clause with existing messages verbatim,
real staged fixtures and no test seams, no `Qt.callLater` coalescing or
idempotence guards, workarounds need user approval, deferred menu rows and
parked areas unchanged. No new C++; the only native touch is the existing
`withVoices` read boundary.

Do not resolve the catalog-outage decision (savecore A016–A026 stay GAP) and
do not close the failed-rebind cfg/status/undo rows A003/A004/A015 or the
mounted stale-save receipt A075. Their technical seams are out of this closed
write set, not additional user-policy questions. Preserve task 78's contract;
never reintroduce `tokens.expire`. No standalone ledger pass:
rows move only in the commit whose predicates prove them.

# Controller verification

After fresh evidence, run `deno task proof check --executed`, then separately:

- `deno task proof sites voicegroupsave/proof.savecore.txt --status GAP`
- `deno task proof sites voicegroupsave/proof.savecore.txt --status PARTIAL`
- `deno task proof sites voicegroupsave/proof.switching.txt --status GAP`
- `deno task proof sites voicegroupsave/proof.switching.txt --status PARTIAL`
- `deno task proof sites voicegroupsave/proof.editor.txt --status PARTIAL`
- `deno task proof sites voicegroupsave/proof.picker.txt --status PARTIAL`
- `deno task proof sites voicegroupsave/proof.synth.txt --status GAP`
- `deno task proof sites voicegroupsave/proof.synth.txt --status PARTIAL`

Expected: 35 selected rows become MATCHED; savecore A005/A006/A080 become
RETIRED-REPRESENTATION. Still open: savecore A003/A004/A015/A075 and
A016–A026, plus the 13 presentation rows — 28 total. Inspect the mounted
failed-rebind, completed-save and picker journeys, not just session predicates.
