# Context

Task 63 — VG04 save/synth/switching journey on the mounted voicegroup dock.
Close the 159 open rows across three ledgers (savecore 80, switching 40,
synth 39) against the dock edit → save → reopen journey, the failed-rebind
and catalog-outage persistence laws, the `-G` switching journey, and the
synth memory-only-until-save journey. No ledger is deletable in this task
(the bank-dirty split rows stay GAP pending the user's decision, ¶6).

1. **Census (verified this freeze)**:
   - `src/checks/voicegroupsave/proof.savecore.txt` — 81 rows: 74 GAP,
     6 PARTIAL, 1 MATCHED (A079). Reference revision
     `c1f165eb1aa49af49c72a3e4f15cf6d9f23b6735`. Counterparts:
     `SaveCoreChecks.swift`, `bank_switching.swift`, `session_save.swift`,
     `tst_ShellVoicegroup.qml`, `bank_sharing.swift`.
   - `proof.switching.txt` — 46 rows: 40 GAP, 6 MATCHED
     (A003/A004/A006/A007/A013/A014). Reference `a7fcaa3e`.
   - `proof.synth.txt` — 42 rows: 36 GAP, 3 MATCHED (A023/A026/A037),
     3 PARTIAL. Reference `a7fcaa3e`.
2. **Fork laws** (`git show fceecd88:src/checks/voicegroupsave/…`):
   - `savecore.cpp` (289 lines): `failedRebindRetainsBinding` (:43-74) —
     missing `-G` typed into the selector publishes the failure (status names
     the arg, cfg holds the missing arg), home id/lease/slot rows/minimum
     size/geometry retained, selector stays enabled, undo restores the home
     binding with a clean document; `catalogOutageRetainsLastValid`
     (:76-110) — hidden `sound/` + catalog refresh reaches the production
     error boundary ("sound directory is unavailable"), groupArgs/home
     binding/controls retained, restore re-settles;
     `releaseEditDirtiesOnlyBank` (:112-135) — release edit converges in
     bank and engine with document AND window clean;
     `undoShortcutRestoresWithoutWrite` (:137-180) — WindowShortcut undo,
     ShortcutOverride leaves the spin focused, one trigger, undo restores
     release + clean document + original disk bytes;
     `unifiedSavePersistsSongAndBank` (:181-198) — dirty save publishes a
     clean receipt, mid bytes AND voicegroup bytes change;
     `queuedSaveSnapshotPreservesNewerEdit` (:199-252) — stale snapshot
     completes inline-false with stale midi bytes and a still-dirty
     document, retry cleans, undo probes leave document-only dirt, fresh
     load carries the edited release; `undoSaveRoundTripsBankBytes`
     (:253-278); `cleanSaveEmitsNoReceipt` (:279-289).
   - `switching.cpp` (266 lines): `switchCarriesUnsavedBankEdit` (:23-65) —
     unsaved release edit survives a `-G` switch as cfg undo, undo replays
     the edit onto the home bank (dirty bank, engine parity), second undo
     restores clean, disk never written; `selectorSwitchUsesUndoableCfgEdit`
     (:66-92) — selector text drives the undoable `-G` seam (document
     dirty), undo restores home binding + clean + selector text;
     `valueCommandSurvivesSourceReplacement` (:93-176) — saved value undo/
     redo resolve against refreshed canonical bytes across a clean `-G`
     round trip, redo-tail re-applies after a restoring save;
     `blankTokenRebasesAcrossSourceReplacement` (:177-266) — blank-slot
     materialization token rebases across the replacement (task-61's
     `applied.materialization` is the Swift token).
   - `synth.cpp` (181 lines): `synthDefinitionsStayMemoryOnlyUntilSave` —
     staged `set_synth_*` macros refresh the published catalog
     (`VgSaveCheckSaw`), synth activation mints a memory-only tone
     (`wav->size == 0`, wave bytes `data[1..5] == 0 21 … 87`, param-named
     symbol), disk + visible combo unchanged pre-save, save writes the
     symbol and the data wiring, wave flips + full undo tail restore the
     baseline bytes with a confirming post-undo save.
3. **Swift current state — the save/switch path exists; proof does not**:
   `DocumentSession.save()` (:440-466) captures, saves, `didSave`s and
   adopts the bank receipt; `selectVoicegroup` (:510-537) loads the
   replacement bank BEFORE retargeting cfg (failed load leaves document,
   lease and history untouched — the failed-rebind law's production half);
   `stepHistory` rebinds a prepared bank before crossing an undoable `-G`
   edit; `applyBankEdit` seals the bank merge; `mintSynth` stays
   memory-only (task-61). `VoiceListController.commitVoicegroupSelection`
   (:365-374) → `ApplicationSession` (:163-176) → `selectVoicegroup` +
   refresh is the selector seam. Store coverage from task-61 to reuse
   unchanged: bank round trip + source preview (S1–S3/S5/S7/S9–S14),
   mint dedup + write gates, packed descriptor bytes, `bankSwitchingParity`
   (switch/return/redo write nothing), `sessionSavePersistence` (save,
   reopen, stale snapshot, lease reuse).
4. **Task-61 reuse (089652fc)**: `ProjectBankEditOutcome.applied` carries
   `materialization`/`materializationToken`; `VoicegroupLoaderChecks`
   context parity; synth write gates (CRLF, byte no-op, collision/bare/
   unwired rejection) and the descriptor journey. This task re-anchors —
   never rebuilds — those predicates.
5. **Bank-close policy**: `-G` retargets only after the replacement bank
   loads (`selectVoicegroup`), undo prebinds across the `-G` edit
   (`stepHistory`); switching never autosaves (`bankSwitchingParity`).
   Bank bytes on disk change only through `save()`.
6. **Open user question — bank edits dirty the song**: `SongHistory`
   folds bank entries into `currentIdentity` (`SongHistory.swift:238,368`;
   `isDirty` at :433), so every bank edit dirties the song document; the
   fork keeps bank dirty separate (`releaseEditDirtiesOnlyBank`,
   `!m_document->isDirty()` beside a dirty bank). Every row whose assert
   is document-clean-beside-dirty-bank stays GAP pending the user's
   decision — the ledger agent identifies them by assert text, the
   implementer proves everything around them.

# Exact write set

- `src/checks/workspace/bank_switching.swift` — switching journey
  predicates (unsaved-edit carry, selector cfg edit, value-command rebind
  survival, blank-token rebase).
- `src/checks/workspace/session_save.swift` — unified-save, queued-save,
  undo-save round-trip, clean-save predicates.
- `src/checks/projectstore/SaveCoreChecks.swift` — failed-rebind +
  catalog-outage store predicates over temp roots.
- `src/checks/projectstore/ProjectStoreSaveChecks.swift` — synth
  wave-flip + full-undo-tail + post-undo-save predicates (extends task-61's
  synth block).
- `src/checks/voicelist/voicelist_session.swift` — selector-switch and
  dirty-split presenter predicates (`session.document.isDirty`, never
  `app.documentDirty`).
- `src/checks/editorqml/tst_ShellVoicegroup.qml` — mounted journeys
  (failed rebind, catalog outage, unified save, selector switch, synth
  activation → save).
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only in `proof.savecore.txt`, `proof.switching.txt`,
  `proof.synth.txt`. No ledger is deleted.

No production Swift, no QML mounts, no CMake changes, no
`ShellQmlTests.swift` change (task-62 stages `fixture_alt.inc` for
`shell-voicegroup`; this task reuses that staging). Contingent production
edits: none at freeze — a RED predicate that exposes a genuine production
divergence stops and reports; the brief re-opens rather than stretching.

# Prerequisites

Task-61 landed (089652fc); its predicates and the `applied` record are
consumed as-is. In-flight task-62 owns `tst_ShellVoicegroup.qml`,
`VoiceListController.swift`, and the `fixture_alt.inc` lane staging —
this task's QML/test edits serialize after 62 settles (same-file
checkpoint, not an interface dependency). Free-parallel with 56/60/66
(disjoint files).

# Interface contract

- Reused unchanged: `DocumentSession.save/selectVoicegroup/undo/redo`,
  `ProjectBankEditOutcome.applied` materialization record,
  `VoiceListController.commitVoicegroupSelection`, task-61's synth
  write-gate and descriptor anchors. Preservation contract: every existing
  check message in touched files stays verbatim.
- New anchors (message-anchored, one per fork clause; strings stay verbatim
  once written; `p:` prefix = presenter-level, rest mounted or store):
  - Store (`SaveCoreChecks`): "a failed voicegroup rebind keeps the home
    lease and publishes the missing arg"; "a catalog outage keeps the last
    valid catalog and binding"; "restoring the sound directory re-settles
    the catalog".
  - Session (`session_save.swift`): "one save persists the song edit and
    the bank edit"; "a stale snapshot leaves the newer document dirty";
    "retrying from the newer state cleans the session"; "undo after save
    round-trips the bank bytes"; "a clean save emits no receipt".
  - Switching (`bank_switching.swift`): "a -G switch carries the unsaved
    bank edit"; "undo replays the carried edit onto the home bank"; "a
    second undo restores the clean baseline without writing";
    "the selector drives the undoable -G seam"; "selector undo restores
    the home binding and selector text"; "value undo and redo resolve
    against the refreshed canonical bytes"; "the redo tail re-applies
    after a restoring save"; "the blank token rebases across the source
    replacement".
  - Synth (`ProjectStoreSaveChecks.swift`): "a staged synth macro reaches
    the published catalog"; "synth activation stages a memory-only tone";
    "the unsaved synth leaves the synth file and combo unchanged";
    "saving writes the synth symbol and its data wiring"; "wave flips
    republish the tone"; "the full synth undo tail restores the baseline
    bytes".
  - Presenter (`voicelist_session.swift`): p: "the selector commit resolves
    display text to the alternate arg"; p: "a failed switch leaves the
    home arg standing".
  - Mounted (`tst_ShellVoicegroup.qml`): "a missing -G names itself in the
    failure"; "undo after a failed rebind restores the home voicegroup";
    "hiding the sound directory surfaces the outage"; "a unified save
    cleans the dock"; "synth activation publishes the param-named symbol".

# Implementation steps

1. Store predicates first (`SaveCoreChecks` failed-rebind over a temp
   root with an unresolvable arg; catalog-outage by hiding `sound/`,
   asserting the error boundary + retained catalog/binding, then restore).
   RED first where the seam is unproved.
2. Session predicates (`session_save.swift`): unified save (mid + bank
   bytes move, clean receipt), queued stale snapshot + retry + undo
   probes, undo-save round trip through a fresh load, clean-save no-op.
   Reuse the file's `stageTestProject`/`sessionOpenAndRecovery` pattern.
3. Switching predicates (`bank_switching.swift`): needs two staged
   voicegroups (mirrors the fork's `fixture_alt.inc` requirement); carry,
   selector seam, value-command rebind survival, blank-token rebase via
   task-61's materialization record.
4. Synth predicates (`ProjectStoreSaveChecks.swift`): stage macros + one
   `set_synth_saw` def into a temp root, refresh the catalog, activate on
   a non-synth DirectSound slot, assert memory-only tone + unchanged disk,
   save, wave flips, full undo tail + confirming save. Reuse task-61's
   mint/save helpers.
5. Presenter predicates (`voicelist_session.swift`): selector resolution
   and failed-switch home-arg standing on `session.document.isDirty`.
6. Mounted journeys (`tst_ShellVoicegroup.qml`) per the anchor list,
   reusing the lane's song-open/wait helpers; run the lanes and hand the
   evidence JSONs to the controller.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter projectstore-savecore --verbose` — store
  rebind/outage predicates + round-trip regressions.
- `deno task verify --filter projectstore-savebank --verbose` — synth
  journey + task-61 write-gate regressions.
- `deno task verify --filter swiftcore-bankhistory --verbose` — switching
  predicates + bank-suite regressions.
- `deno task verify --filter swiftcore-projectsession --verbose` —
  session-save + voicelist predicates + regressions.
- `deno task verify:shell --filter shell-voicegroup --verbose` — mounted
  journeys + dock regressions.
- Runtime prerequisites: macOS (all five lanes are `Platform::MacOS`);
  working application audio (the dock binds audio on song open).
- RED evidence for the unproved seams (failed-rebind store path,
  catalog-outage boundary, synth activation) before they pass.

# Task-specific constraints

- Hot files: `tst_ShellVoicegroup.qml` (shared with in-flight 62 —
  serialize after it); `ShellWindow.qml`, `ShellPresenter.swift`,
  `ApplicationSession.swift`, `DocumentWorkspace.swift`,
  `EditorSurface.qml`, `PianoGrid.swift`, `tst_EditorDrawer.qml` untouched
  (disjoint from 56/60/66).
- No new C++; no code comments (delete stale ones in touched regions).
- One message-anchored predicate per fork clause; mounted proof for input
  delivery (selector activation, failure surfacing); store-level only
  where the dock adds no observable; presenter-level only for the
  document-clean/bank-dirty split (never `app.documentDirty`, which folds
  in `bankDirty`).
- Keyboard priority: no second dispatcher, synthetic forwarding, or focus
  memory — the undo-shortcut law is proved through the window undo path,
  never a new shortcut handler.
- Implementers never edit ledgers; the controller delegates them to the
  ledger agent. Mapping (re-verify each row against the evidence JSONs
  and the fork sources cited above):
  - savecore: A001–A015 → failed-rebind anchors (A012/A013 dock-geometry
    and minimum-size clauses → `RETIRED-REPRESENTATION`, pinning QWidget
    dock geometry; verify at Reference revision c1f165eb); A016–A026 →
    catalog-outage anchors; A027–A031 stay GAP (bank-dirty split, ¶6);
    A032–A045 → undo-shortcut anchors except each
    `!m_document->isDirty()`-beside-dirty-bank clause, which stays GAP
    (¶6); A046–A052 → unified-save anchors (A051 keeps its S anchor,
    upgraded where the new predicate executes); A053–A067 → queued-save
    anchors; A068–A076 → round-trip anchors (A076 likewise); A077–A081 →
    clean-save anchors (A079 already MATCHED, untouched).
  - switching: A001–A007 → carry anchors (document-clean clauses stay GAP
    per ¶6); A008–A016 → selector-seam anchors; A017–A029 → value-command
    rebind anchors (ditto for the `!isDirty` clauses); A030–A046 →
    blank-token rebase anchors over the task-61 record.
  - synth: A001–A013 → macro-staging + catalog-refresh anchors; A014–A022
    → memory-only tone anchors; A023/A026/A037 stay MATCHED; A024/A025/
    A027–A036 → save/write + wave-flip anchors; A038–A042 → undo-tail +
    post-undo-save anchors. Existing PARTIALs flip only with executed
    predicates in the stated fixture state.
- If a mounted predicate exposes a divergence no contingent fix can
  justify (behavior law, not presentation), stop and report — do not
  narrow the predicate.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed` (no ledger fully closes; the
   remaining GAPs are exactly the ¶6 split rows plus any named deferral).
2. `deno task proof sites --area voicegroupsave` confirms three surviving
   ledgers and lists the GAP rows for the user's bank-dirty decision.
3. Confirm `fixture_alt.inc` staging was reused from 62 (no duplicate
   `ShellQmlTests.swift` edit in this task's diff).
