# Task 88 brief — selection-scope transitions publish exact payloads; clipboard transport stays native-real

# Context

Own the mounted range/note selection journey and the native clipboard command
journey. The gap is the consumer-visible transaction detail: every track-scope
gesture and time/note commit already runs, but its published
`SelectionTransition` payload endpoints, its one-publication counts, its
lane-scope sanitize survivors and its native MIME transport laws have no
executing predicates. This is not a ledger cleanup and not a new selection
model; the session already owns the behavior.

1. **Verified census: 39 selected rows of 83 open** across the four clipboard
   ledgers, queried at HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`:
   - `src/checks/clipboard/proof.selectioncheck_core.txt` — 13 open, all
     selected: PARTIAL A010, A014, A016, A018, A027, A028, A032, A034, A037,
     A041; GAP A029, A033, A038.
   - `src/checks/clipboard/proof.selectioncheck_tracks.txt` — 47 open, 23
     selected: PARTIAL A009, A019, A021, A023, A025, A030, A037, A043, A049,
     A050, A056, A057; GAP A010, A011, A013, A014, A020, A024, A031, A033,
     A034, A035, A036.
   - `src/checks/clipboard/proof.clipmime_test.txt` — 4 GAP, 3 selected:
     A005, A013, A014.
   Total: 17 GAP + 22 PARTIAL. Left open (44): clipmime A017 and all 19
   `laneselection_test` rows (endpoint `laneSet` ingress and lane-aware
   projection `hitTest`: future automation-selection surface, not selected by
   task 85); tracks A047 (empty used-track tempo query pins the fork's explicit
   mask parameter the parameterless Swift query cannot express), A074 (fork
   in-place song-swap reset; Swift constructs a fresh per-tab session) and the
   selection-remap family A080–A083, A084, A085, A088–A094, A096–A100,
   A102–A105 (structural remap lifecycle is a separate surface; it also
   borders task 90's roll remap work).
2. **Fork laws**, read at `fceecd88`:
   - `src/checks/clipboard/selectioncheck_core.cpp:29-84`
     (`noteSelectionSanitizesAndExcludesTime`): after a time commit clears
     notes, setting `{NoteId 19}` preempts the time selection, stores exactly
     `{19}` (A014), and publishes one combined notification (A016); an
     inactive time commit preserves the notes and publishes nothing (A018).
   - `:87-127` (`timeSelectionAndScopeCommitAtomically`): with primary 3, a
     commit over scope {1, 20} stores {1, 3} — out-of-range dropped, primary
     forced in (A027); the first commit's transition carries an empty previous
     track time (A029) and payload scope {1, 3} (A032); a commit that finds a
     competing note selection clears it inside the same publication (A033,
     A037's mask); the second commit stores {2, 3} (A034), reports an empty
     previous scope because the intervening note selection had cleared the
     time selection (A038), and payload scope {2, 3} (A041).
   - `src/checks/clipboard/selectioncheck_tracks.cpp:31-117`
     (`trackScopeGesturesPreserveOrClearAtTheRightBoundary`): the toggle
     handoff transition reports previous and current track-time endpoints
     30/60 with scopes {1,3}→{3} (A010, A011, A013, A014); the collapse
     reports payload scopes {3,4}→{3} (A020, A021); the inclusive range
     reports {3}→{3,4,5} (A024, A025); plain-on-another-track makes that
     track primary with stored scope {3} (A030, A031) and its transition
     carries previous endpoints 30/60, previous scope {1} (A034, A035, A036)
     and a cleared current track time (A037).
   - `:118-158` (`coverageQueriesAndLaneScopeSanitization`): a pitch-bend
     lane is covered under a track-scope selection (A043); lane-list sanitize
     over valid, duplicate and out-of-range lanes keeps exactly {{2, 7}}
     (A049) with the tempo flag preserved (A050); a sanitize that drops every
     lane leaves no lanes and no tempo flag observable (A056, A057).
   - `src/checks/clipboard/clipmime_test.cpp:228-257`: a production
     `writeClipboard` leaves the clip MIME readable on the live clipboard
     (A005); publishing foreign plain text through the real clipboard
     displaces the clip MIME so it is absent (A013) and decodes to no song
     clip (A014).
3. **Current Swift/QML**, verified at `e334b318`:
   - `src/swift/app/DocumentSession.swift:40-56` defines
     `TrackTimeSelection` (startTick/endTick/trackScope/active) and
     `SelectionTransition`; `DocumentSession+Internals.swift:41-79`
     (`publishChange`/`flushStateChanges`/`emitSelectionTransition`)
     coalesces every selection change inside one `withStateChanges` into one
     transition carrying previous/current `trackTimeSelection`.
   - `src/swift/app/DocumentSession+Selection.swift:21-50`
     (`applyTimeSelection`) forces the primary into the stored scope, drops
     out-of-range tracks and lanes, and clears a competing note selection
     inside the same publication (`:47`); `:83-123`
     (`adjustTrackScope`) owns plain/toggle/range including the
     plain-elsewhere time clear; `:8-19` (`setSelectedNotes`) owns the note
     preemption.
   - `src/checks/editcheck/SelectionChecks.swift:36-101`
     (`clipboardUnifiedModelChecks`) already drives gestures with a
     transition observer but only reads `transitions.last` scope fields; the
     other three groups (`:104-598`) cover note/time/lane value laws. The
     fixture's primary is track 0, so the forced-primary laws are never
     exercised.
   Forward pointer: task 87 (roll keyboard surface) consumes this task's
   mounted range/clipboard contract — the preserved selection APIs, the
   coalesced single-transition publication and the native clip-MIME journey —
   at its final gate. Keep those surfaces stable; 87 owns `tst_ShellWindow.qml`
   after task 83 and adds its own keyboard smoke there, outside this write set.
   - `AutomationTimeSelection.covers(_:usedTracks:)` is public
     (`src/swift/app/drawer/automation/AutomationLaneProjection.swift:238`)
     and callable from the editcheck target, so the pitch-bend coverage
     predicate needs no automation-file write.
   - `src/checks/editorqml/tst_ShellClipboard.qml` is the mounted lane: it
     opens Route 101 in production `ShellWindow`, drives real pointer/key
     copy/cut/paste, and reads the native clipboard through
     `GridInputClipProbe` (`src/checks/editorqml/GridInputClipProbe.swift`,
     production `pd_clipboard_read`/`pd_clipboard_write`). The lane records
     executed `test_` function names in
     `build/proof-evidence/shell-clipboard.json`, which is the evidence QML
     S entries classify against (`tools/proof_reader.ts:559-572`).
   - Track-header clicks are the mounted scope gestures:
     `src/swift/app/headers/TrackHeadersInput.swift:91-93` maps
     Ctrl→`.toggle`, Shift→`.range`, plain→`.plain` into
     `session.adjustTrackScope`.

# Exact write set

- `src/checks/editcheck/SelectionChecks.swift`
- `src/checks/editorqml/tst_ShellClipboard.qml`
- `src/checks/clipboard/proof.selectioncheck_core.txt` — only the 13 selected
  rows and their predicates.
- `src/checks/clipboard/proof.selectioncheck_tracks.txt` — only the 23
  selected rows and their predicates.
- `src/checks/clipboard/proof.clipmime_test.txt` — only the 3 selected rows
  and their predicates.
- `src/swift/app/DocumentSession+Selection.swift` — **only** for a
  RED-exposed divergence in a selected law. If touched, the bank-token
  paths (`ServiceBankAction(token:materializedBlank:)` recording and its
  replay in `DocumentSession.swift`) stay byte-identical; task 78's ruling
  (fork-matching blank-token rebase) is settled behavior, not an open
  decision, and must not regress.

Production edits are limited to a demonstrated selected-law mismatch; do not
manufacture a diff. No write-set file overlaps 79–82. The mounted command path
still consumes settled routing behavior: **rebase after 79 lands** when
reading automation commands and **rebase after 81 lands** when reading
`EditorCommandRouter`. `DocumentSession.swift`, `ShellPresenter.swift`,
`ApplicationSession.swift`, `ShellWindow.qml`,
`AutomationSelectionCommands.swift` and all four prior-wave QML lanes remain
outside the write set.

# Prerequisites

Sprint-3 §8 split/repair is settled and task 78 has landed (54c7f97a). This
task consumes only existing session, clipboard and header-input interfaces;
it introduces no new interface. Group A is file-disjoint; task 87 consumes the
accepted range/clipboard behavior contract in Group B.

# Interface contract

- Preserve every existing selection API: `setSelectedNotes(_:)`,
  `applyTimeSelection(_:)`, `adjustTrackScope(track:action:)`,
  `selectPrimaryTrack(_:)`, `clearSelectedNotes()`, `clearTimeSelection()`,
  `timeSelectionCoversTrack(_:)`, `timeSelectionCoversTempo()`, and the
  `addSelectionTransitionObserver`/`removeSelectionTransitionObserver` pair.
  No new bridge API, no new observer kind, no public exposure of
  `trackTimeSelection`.
- Extend `clipboardUnifiedModelChecks` (or add sibling private functions in
  the same file) with a primary-3 fixture: assert, through the transition
  observer, exactly one new transition per gesture with the full payload
  (previous/current startTick, endTick, trackScope) for the handoff,
  collapse, range and plain-elsewhere journeys; assert the stored-scope and
  note-clearing laws of the core commit sequence including the
  forced-primary union and the intervening-note-selection cleared previous
  payload; assert the lane-sanitize survivors, the tempo flag and the
  dropped-selection emptiness; assert
  `AutomationTimeSelection.covers(.pitchBend(track:), usedTracks:)` true
  under a track-scope selection covering that track.
- Dispositions: 32 rows MATCHED with one new literal message anchor per
  clause (distinct literals per row group: handoff endpoints, collapse
  payload, range payload, plain-elsewhere primary/scope/payload/cleared
  current, sanitize survivors, tempo flag, dropped emptiness, bend coverage,
  preemption count and stored notes, inactive-commit silence, forced-primary
  stored/payload scopes, empty first previous payload, cleared second
  previous scope, competing-note clearing). 7 rows retire as
  `RETIRED-REPRESENTATION`: core A010, A028, A037 and tracks A009, A019,
  A023, A033 — each pins only the fork's combined
  `kNoteSelection|kTimeSelection|kTrackScope|kPrimaryTrack` bitmask identity
  on `EditorSelectionModel`'s NotificationLog
  (`selectioncheck_core.cpp:11-17`, `selectioncheck_tracks.cpp:22-29`),
  which Swift's single coalesced `.selection` domain publication plus
  `SelectionTransition` payload supersedes; the one-publication behavior
  those masks carried is asserted by the new payload predicates and the
  existing S008/S011/S013/S018/S019 evidence. No check re-creates a mask.
- QML predicates: extend `tst_ShellClipboard.qml` with new `test_` functions
  carrying per-clause anchors: mounted Copy makes native clip MIME readable
  and decodable (A005). Click the production `songListSearch` TextField
  (`SongsPanel.qml:45-52`), type and select foreign text, then use native Copy.
  This displaces clip MIME (`readClipJson()` empty, A013) and decodes to no
  clip (`clipSummary()`, A014). Clear the filter and leave text focus before
  checking that song Paste is unavailable; do not add a test-only TextEdit.
  The three clipmime rows map to these QML S entries; their Swift codec
  counterparts S001–S003 stay unchanged.
- Mounted scope-gesture smoke (no ledger row): sweep a time range on the
  mounted roll, plain-click another track header (Copy becomes unavailable —
  the time selection cleared), restore the sweep and toggle/range-click
  headers so a subsequent Copy payload's tracks match the reshaped scope.
- Preserve every existing message verbatim, including "a track-scoped range
  is owned by the document session", "plain on another track clears the time
  selection", "plain on the primary track preserves the time interval",
  "toggle hands primary to the surviving track", "range expands inclusively
  from primary to target", "a note selection clears the active time
  selection", "remap moves the stored scope with the selected track" and the
  note/time/lane group messages. Do not relabel existing value predicates as
  new payload evidence.

# Implementation steps

1. Add the primary-3 fixture and payload/count/sanitize predicates first. The
   controller executes on the settled group only; report an honestly green
   baseline where the existing machinery already satisfies the law.
2. Drive each gesture through the public session API with one transition
   observer attached; read `transitions.last` (and the array count delta)
   after each completed gesture, never a captured stale projection. The
   plain-elsewhere journey asserts exactly one transition across the whole
   gesture (nested `withStateChanges` coalesces).
3. Add the lane-sanitize and bend-coverage predicates with real document
   state; out-of-range lanes enter through the public
   `applyTimeSelection(.lanes)` ingress only.
4. Add native-MIME Copy, foreign-text Copy through the real song filter, and
   the header scope-gesture smoke. Reuse the lane's existing
   `openRoute101`/`waitForNative` helpers; no new probe type, no new seam.
5. Fix only demonstrated divergences in `DocumentSession+Selection.swift`,
   preserving the bank-token paths. Run the acceptance lanes after the write
   group settles; attach only the executed anchors to the selected rows in
   the same surface change, including the 7 retirements.

# Acceptance predicate

Controller-run on the settled built tree, each invocation capped at 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — payload,
  count, sanitize, coverage and preemption predicates;
  `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shell-clipboard --verbose` — mounted
  native and foreign MIME plus scope-gesture journeys and existing
  clipboard regressions; `build/proof-evidence/shell-clipboard.json`.

Registration is unchanged: `runClipboardSelectionChecks` at
`src/checks/workspace/SessionChecks.swift:90` and the swiftcore suite entry
`src/checks/checkcatalog.cpp:125`; the shell entry at
`src/checks/editorqml/ShellQmlTests.swift:68`. Evidence writer:
`tools/run_checks.ts:426-434`. The first lane does not prove native
transport; the second is required even if every Swift predicate passes, and
conversely the QML lane alone cannot close the session payload rows.

# Task-specific constraints

Incorporate **sprint-3 §8 Wave constraints and §9 policy**: Swift 6.4 idioms,
borrowed/fixed-size storage where appropriate, no hot-path allocations,
two-line comments, base-font sizing and WCAG AA. Keep the sole window
dispatcher; no second dispatcher, synthetic forwarding, focus memory or bare
Space capture in chrome. One anchored predicate per clause, existing messages
verbatim, real fixtures, no seams; no `Qt.callLater` coalescing or idempotence
guards. Workarounds need user approval. Deferred menus and parked areas stay
out. No new C++; native text Copy uses the existing production song filter.

This is not permission for a selection-model refactor, a notification-domain
redesign or sweep of unselected clipboard rows. A017 remains GAP: its decode
failure status belongs to a separate failure-publication surface through
`ShellPresenter.statusText`/`ApplicationSession.operationFailed` or automation
paste. That is a technical scope boundary, not another user-policy decision.
The 19 laneselection rows are not owned by task 85; the selection-remap family
also stays outside this wave. Ledger changes accompany their executing
surface, never a standalone pass.

# Controller verification

After both lanes have fresh evidence, run `deno task proof check --executed`.
Then run, separately:

- `deno task proof sites --area clipboard --status GAP`
- `deno task proof sites --area clipboard --status PARTIAL`

Exactly the 39 selected rows are expected to leave GAP/PARTIAL (32 MATCHED,
7 RETIRED-REPRESENTATION); 44 stay open with the reasons above. Confirm each
payload clause reads `startTick`, `endTick` and `trackScope` on both
transition sides, that the forced-primary rows ran with primary 3 (not the
old primary-0 fixture), and that the QML production-field foreign-MIME journey
appears in `shell-clipboard.json`'s function list. No ledger is deleted.
