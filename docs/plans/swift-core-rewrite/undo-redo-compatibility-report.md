# Undo/redo compatibility audit

## Verdict

**Do not accept history parity or retire the C++ reference on the present evidence.**

The rewrite preserves the intended architecture of one history, stable document identities, grouped edits, and snapshot-based restoration. It has not abandoned undo/redo. However, this audit reproduced four behavioral defects in the frozen Swift Core, found two additional source-confirmed bank-history mismatches, and found coverage claims that do not establish their named reference behavior.

These are findings for the implementer to repair, not permission to redesign user-visible history behavior. The existing C++ implementation and its observable regression contracts are the compatibility reference. Replacing command subclasses with Swift state snapshots is acceptable; changing operation ordering, conflict policy, merge boundaries, or retained MIDI data without approval is not.

**Scope qualification:** these are Swift replacement/backend findings, not a claim that the currently running legacy UI already exhibits them. The inspected `swiftroll` presenter still uses `SgcCommandPipe` / `DocumentFeed`; real-window cutover evidence remains separate.

## Evidence and provenance

- Worktree: `/Users/spencer/dev/cProjects/porydaw/.worktrees/swift-qml-grid`.
- HEAD when captured: `bdb63b535358854a7e8ef4458ba2e8eff55bcaf6`. Reviewed working files include changes beyond that commit; this is not a commit-only review.
- Frozen source directory: `/var/folders/tm/rx2sb_ks5dx5x81c3vgsrvtm0000gn/T/porydaw-history-audit-9mrx5ya_`.
- `snapshot.json` records full SHA-256 hashes. All source line references below refer to this snapshot; ongoing implementation can move live line numbers.
- Runtime probe: unmodified frozen `src/swift/core/*.swift`, compiled with Apple Swift 6.3.3 in Swift 6 language mode, target `arm64-apple-macosx26.0`.
- No production sources or permanent tests were modified. The only repository addition from this audit is this report.
- No full application build, native service fixture run, Windows run, or real-window interaction run was performed. Bank service findings below are source comparisons, not executed native-bank reproductions.

Key frozen file hashes, abbreviated:

| File | SHA-256 prefix |
|---|---|
| `src/swift/core/SongHistory.swift` | `944023d5441e26b0` |
| `src/swift/core/SongDocument.swift` | `5c015ffc158a5e66` |
| `src/swift/app/DocumentSession.swift` | `d166d3a6ff29670a` |
| `src/swift/app/ProjectService.swift` | `1affcc19e110246e` |
| `src/checks/swiftcore/SessionChecks.swift` | `86b1a261558bee0a` |
| `src/checks/swiftcore/NoteChecks.swift` | `9d8ee075426106b7` |
| `src/checks/swiftcore/EventChecks.swift` | `823da364a6962ceb` |
| `docs/plans/swift-core-rewrite/coverage-ledger.json` | `67d051299221a502` |

### Correction to earlier conversational findings

The earlier `SessionChecks.swift` block labeled “Auxiliary checks for ledger completeness,” containing blanket `expect(true)` claims, **is absent from this report's newer frozen snapshot**. The file had grown to 1,520 lines and contains additional real scenarios. Do not treat the old block as an outstanding defect without inspecting the current source.

Remaining coverage mismatches are documented under H7. A success assertion inside an expected-error branch is not, by itself, the same thing as the earlier blanket block; assess what the branch and surrounding assertions actually prove.

Also, my earlier blanket statement that bank conflicts should leave history fixed was incomplete. The reference distinguishes initial conflicts, stale undo/redo conflicts, and hard errors. H2 records the actual policy.

## Findings

### H1 — Critical: suspended bank Undo can skip a newer edit and mark unsaved data clean

**Evidence: reproduced against unmodified frozen Swift Core.**

`SongHistory.undo()` reads the bank entry at the current index, awaits its action, then decrements the *current mutable index* (`src/swift/core/SongHistory.swift:108–118`). `redo()` has the analogous increment (`122–132`). There is no transition ownership protecting that index across suspension. `DocumentSession.undo()/redo()` simply await these methods (`src/swift/app/DocumentSession.swift:129–146`); the session exposes its mutable document.

Reproduction:

1. Set document priority to 1 and mark that snapshot saved.
2. Record a confirmed bank-history action.
3. Start Undo; suspend the bank action before completion.
4. Set document priority to 2 while the bank action is pending.
5. Complete the bank action, then invoke Undo again.

Observed:

```text
PENDING_BANK_UNDO completed=true priority=2 isDirty=false canRedo=true bankReplayCalls=1
NEXT_UNDO priority=2 bankReplayCalls=2
```

The unsaved priority-2 state is reported clean. The next Undo replays the bank action a second time rather than restoring priority 1. This is a history/state-identity consistency defect, not merely a disabled-button issue.

The probe uses a controlled suspending `BankHistoryAction` to exercise production history. It does not simulate native persistence or establish present-day UI reachability.

**Reference:** `src/ui/voicegroupviewcache.cpp:13–18,88–95` permits one pending transition and gates actions/close; `src/ui/workspaceui_voicegroup.cpp:62–80` refuses further history requests while the bank gate is closed. `src/ui/workspaceui.h:108–109` explicitly describes gating history mutation, Undo, and Redo. `src/checks/voicegroup/tst_voicegroupviewcache.cpp:254–324` exercises transition gating and resolution.

**Required result:** an in-flight bank transition must never consume a different entry, replay twice, or make newer unsaved data clean. Preserve the reference's user-facing gating; if the replacement deliberately permits concurrent document edits, it needs a correct transaction-ordering contract and explicit approval for changed interaction behavior. A serial native worker or actor annotation alone is insufficient: Swift code resumes after an `await` against mutable history.

**Regression scenarios:** delayed bank Undo and Redo versus a new document edit; repeated Undo/Redo while pending; initial bank edit versus history mutation; completion/failure/close. Assert document bytes/configuration, dirty state, bank state, and the next observable undo/redo operation, not just `canUndo`.

### H2 — High: stale bank-history conflicts block progress instead of removing obsolete entries

**Evidence: source-confirmed compatibility mismatch; native-bank reproduction not run.**

Reference behavior is explicitly three-way:

| Outcome | Reference history behavior |
|---|---|
| Initial edit conflicts | No entry is recorded |
| Undo/Redo conflicts because its entry is stale | Remove that obsolete entry; do not mutate the conflicting bank |
| Hard service failure | Keep the entry/index available; do not cross it |

Sources: `src/ui/voicegroupviewcache.cpp:54–79`; `src/core/songhistory.cpp:258–277`. Reference regressions at `src/checks/voicegroup/tst_voicegroupviewcache.cpp:175–204` assert removal and continued history availability.

In Swift, `bankEditCompletion` translates a conflict into `ProjectServiceError.bankConflict` (`src/swift/app/ProjectService.swift:557–579`). `ServiceBankAction.apply` propagates it (`365–392`), and `SongHistory.undo()/redo()` propagate the error without removing the stale entry (`108–132`). There is no separate conflict-resolution path. A repeatedly conflicting top entry can therefore obstruct older usable history.

**Required result:** preserve all three reference outcomes, including the distinction between semantic conflict and hard failure. Do not fix this by dropping entries for every thrown error.

**Regression scenarios:** stale scalar Undo, stale scalar Redo, stale blank-materialization token, initial-edit conflict, and hard service error. After each, verify bank bytes/value, document identity, and which operation the next Undo/Redo reaches.

### H3 — High: a self-cancelling bank merge retains a redundant Undo step

**Evidence: source-confirmed compatibility mismatch; native-bank reproduction not run.**

For adjacent mergeable edits to the same field, `A → B → A` removes the command in C++ (`src/core/songhistory.cpp:129–148`). `src/checks/voicegroup/tst_voicegroupviewcache.cpp:223–229` explicitly expects zero remaining entries for that sequence.

`ServiceBankAction.merged()` returns an action whose oldest `before` can equal its final `after` (`src/swift/app/ProjectService.swift:395–406`). `SongHistory.recordConfirmedBank()` replaces the previous action but has no cancellation/removal outcome (`src/swift/core/SongHistory.swift:77–88`). Unlike document groups, the bank action contract cannot report that a merged entry has become obsolete.

**Required result:** after `pan 10 → 20 → 10`, the next Undo reaches the preceding meaningful operation. No redundant bank replay remains. Preserve non-merging cases: different slot, different bank, changed-field boundary, blank materialization, and a saved bank boundary.

**Regression scenarios:** self-cancelling merge with and without a preceding document entry; save between edits; mixed scalar fields; blank-slot materialization followed by a scalar edit.

### H4 — High: a rejected mixed stationary/moving note batch instead deletes a participant and destroys Redo

**Evidence: reproduced against unmodified frozen Swift Core.**

Setup: two notes at tick 0, duration 4, pitches 60 and 62. Establish a redo branch. Request `moveNotes([A, B], toPitches: [60, 60])`.

**Reference:** the unchanged participant A still participates in batch collision validation; the conflicting batch is rejected (`src/core/songdocument.cpp:1454–1466`, overlap rejection at `1139–1147`). No new history entry or redo invalidation should occur.

**Swift:** `relocate` removes unchanged participants from both collision spans and edited IDs (`src/swift/core/NoteEditing.swift:235–252`). B is treated as the sole edited note and A as a bystander that can be deleted.

Observed after starting from a clean state with Redo available:

```text
STATIONARY_PARTICIPANT notes=1 isDirty=true canRedo=false
```

Undo restores the two notes, but the previously available redo branch is already discarded. This is directly relevant to history compatibility: a reference-rejected operation becomes a destructive, history-producing edit.

**Required result:** preserve all selected participants during batch validation, including unchanged ones. Rejection must leave data, identities, revision, dirty state, and redo availability unchanged.

### H5 — High: moving a note changes retained note-off bytes; Redo restores the altered payload

**Evidence: reproduced against unmodified frozen Swift Core.**

Setup: import a note ending with status `0x80` and release velocity 64. Move it four ticks, Undo, then Redo.

**Reference:** copies the original end event and changes only the required position/pitch (`src/core/songdocument.cpp:1420–1429`).

**Swift:** `insertMoved` synthesizes `0x90` with velocity zero (`src/swift/core/NoteEditing.swift:394–403`).

Observed end-event payloads:

```text
original: status=128 data0=60 data1=64
moved:    status=144 data0=60 data1=0
undo:     status=128 data0=60 data1=64
redo:     status=144 data0=60 data1=0
```

Undo does restore the original snapshot. The defect is the edited/redo state, which silently discards MIDI payload information the reference preserves. Do not describe this as a total failure of snapshot restoration.

**Required result:** retain the original end-event form and payload when relocation does not semantically modify them. Assert exact retained bytes on edit, Undo, and Redo for both explicit note-off and velocity-zero note-on endings. Check resize/overlap paths that reuse this helper as well.

### H6 — High: multi-note range insertion records an overlapping result and Redo reproduces it

**Evidence: reproduced against unmodified frozen Swift Core.**

Setup: stationary note S at pitch 60 covering `[0,100)`. Apply one `RangeEdit` adding notes at `[10,20)` and `[30,40)` on the same track/pitch.

**Reference:** the stationary head survives only through tick 10. Its overlap resolver evaluates incoming spans against the progressively shortened stationary note (`src/core/songdocument.cpp:1161–1187`).

**Swift:** `TimeEditing.resolveCollisions` loops over incoming spans, repeatedly deriving the stationary note boundaries from the original reference rather than the updated candidate (`src/swift/core/TimeEditing.swift:845–862`).

Observed projected intervals:

```text
RANGE_MULTIPLE_SPANS stationaryDuration=20 expected=10
RANGE_NOTES ["0..20", "10..20", "30..40"]
RANGE_HISTORY undoRestoresOriginal=true redoRestoresRecordedState=true
```

Undo correctly restores the original state; Redo correctly restores the recorded state, but that state contains a reference-incompatible overlap. This is an edit-semantic defect adjacent to history, not a separate failure of the stack's snapshot mechanism.

An initial diagnostic predicted stationary duration 30 from source inspection and stopped on that expectation. The completed probe established the actual projected duration as 20; this report uses the executed result, not the initial prediction.

**Required result:** the accepted transaction yields `[0,10)`, `[10,20)`, `[30,40)`; one Undo restores the original note and one Redo restores exactly the accepted non-overlapping result. Include tail-trim and covered-note variants only where they exercise distinct collision behavior.

### H7 — High: named coverage and ledger acceptance overstate actual history verification

**Evidence: assertion and ledger inspection, not a fresh harness run.**

The old blanket pass block is gone, but unrelated assertions still carry history-coverage IDs:

| Frozen Swift assertion | Claimed reference contract | What is actually checked |
|---|---|---|
| `SessionChecks.swift:533–535` | `songHistory_mergePreservesOldestBeforeFreshAfter` | One configuration Undo restores a flag; no merged sequence |
| `SessionChecks.swift:536–538` | `songHistory_cancellingMergeRemovesEntry` | Timeline sample remains 19,200; no cancelling merge |
| `SessionChecks.swift:581–583` | `songHistory_savedBoundaryRefusesMerge` | Deleted-note selection is pruned; no save boundary |
| `SessionChecks.swift:1460–1489` | `coordinatorRoutesTransitionsAndGates` | A synchronous tempo edit/Undo leaves bank slots and lease unchanged; the comment explicitly excludes the race |
| `SessionChecks.swift:1492–1496` | `historyLifecycleAndStaleTransitions` | `canUndo` is true; no pending transition or stale conflict |

Reference contracts: `src/checks/project/identity.cpp:196–253` and `src/checks/voicegroup/tst_voicegroupviewcache.cpp:122–324`.

The frozen ledger honestly leaves the two Task 6 view-cache cases `pending`; do not claim those were already accepted. However, some earlier entries are marked `verified` with “all observable assertions” despite narrower Swift checks:

- `editcheck/EditCheckTest::noteBatchCollisionRejects`: the reference establishes a redo branch before rejected batches and later checks exact undo/redo state (`src/checks/editcheck/tst_songdocument_songnotes.cpp:128–176`). The listed Swift whole-batch rejection assertion does not establish that entire contract.
- `editcheck/EditCheckTest::rawEventMutate`: the reference fully rewinds the mutations and compares encoded baseline bytes (`src/checks/editcheck/tst_songdocument_songraw.cpp:102–104`). The named Swift assertions check opaque insertion and end-tick clamping (`src/checks/swiftcore/EventChecks.swift:179–188`), not that rewind.
- `rawEventReorder`: the Swift assertions at `EventChecks.swift:162–177` check bounds and the forward reorder; they do not demonstrate the reference undo/redo sequence.

Passing the old C++ suite alongside a narrower Swift suite does not fill the Swift coverage gap.

**Required result:** each accepted ledger row must map to assertions that exercise its actual required behavior. Separate core behavior from UI-only aspects. Preserve useful new assertions under truthful identities; do not attach an unrelated legacy ID to inflate equivalence. Unsupported cases remain unverified or receive an explicitly approved exclusion, not a fabricated pass. Do not recreate an absent editor solely to satisfy a misclassified UI row.

## What is preserved, and what remains unproven

| Contract | Current evidence | Remaining qualification |
|---|---|---|
| Basic document save → edit → Undo clean → Redo dirty | Executed successfully in isolated probe | Not native file persistence |
| Document snapshot restoration | Probe restored original range state and original note-off payload on Undo | Does not make the forward edit semantically correct |
| Stable note IDs across move/Undo/Redo | Real assertions in `NoteChecks.swift:264–273`; allocator is separate from restored state | Full duplication/remap contract needs its own scenario |
| Group origin and returned-to-origin document state | Real scenario in `NoteChecks.swift:238–262`; entry-removal path in `SongHistory.swift:153–164` | Must prove next Undo reaches the correct prior entry, plus actual caller boundaries |
| New accepted document edit truncates Redo; no-op commit returns before recording | `SongDocument.swift:282–289`, `SongHistory.swift:148–169,186–188` | Rejected batch preservation must be exercised with an existing redo branch |
| Matching save seals merge; stale document snapshot rejected | `SongDocument.swift:275–279`, `SongHistory.swift:72–75`; real `NoteChecks.swift:280–302` scenario | Native in-flight save, bank save boundaries, failure, and reopen remain separate |
| Bank entries preserve document identity | `SongHistory.swift:86–87`; real checks in `NoteChecks.swift:319–343` | Bank dirty state and mixed-history traversal require service-backed assertions |
| Scalar bank Undo/Redo, blank materialization, ordinary scalar merge | Concrete scenarios exist in frozen `SessionChecks.swift` | Not executed in this audit; do not infer conflict/gating coverage from them |
| Real keyboard/gesture grouping and focus routing | Presenter still uses the legacy command/feed path | Not replacement-Core integration evidence |

### Integration contract requiring explicit resolution, not an assumed bug

The new grouped `moveNotes`/`resizeNotes` APIs evaluate supplied deltas against the stored group origin (`NoteEditing.swift:94–110,130–152`). Current Swift checks deliberately pass cumulative offsets (1, 2, 0). The C++ command machinery accumulates incremental keyboard deltas.

This API difference is not automatically a user-visible regression: the replacement presenter has not yet been wired. Do not blindly change it to incremental semantics and break origin-relative pointer gestures. At cutover, prove that repeated arrows continue moving/resizing, reversal restores trimmed neighbors, release or selection/command changes terminate the group, and a save cannot be merged through. Use the real input path, not direct calls that bypass its grouping decisions.

## Required acceptance scenarios

These are behavioral gates for repair, not instructions to preserve the old class hierarchy:

1. Mixed document/bank history traverses in order; each successful transition changes exactly the intended state.
2. Pending bank transitions cannot corrupt index/identity, lose a newer edit, replay twice, or mark unsaved state clean (H1).
3. Initial conflict, stale Undo/Redo conflict, and hard error follow their distinct reference policies (H2).
4. Scalar bank `A → B → A` cancels; field/slot/bank/materialization/save boundaries prevent inappropriate merges (H3).
5. Rejected/no-op operations preserve both the current state and any existing redo branch (H4).
6. Accepted edit → Undo → Redo preserves exact required event bytes, identities, configuration, tempo, and remaps; forward edits themselves match reference semantics (H5–H6).
7. Saving at a history position separates the next merge run; undo/redo across that position produces the correct clean/dirty state. Older completion never clears newer edits.
8. History groups end at the actual input boundaries: command change, selection change, key release, gesture commit/cancel, and save. Returning to origin removes the redundant entry while notifying observers.
9. Real bank save/reopen confirms bytes and state; failure assertions distinguish bank-stage failure from a later MIDI-stage failure. A session's cached dirty flag alone does not prove the native bank's persistence state.
10. Replacement UI routing proves Undo/Redo through registered commands and relevant focus surfaces after cutover. Core tests and legacy-window tests are different evidence.

## Verification record and implementer commands

### Executed by this audit

From the frozen source directory:

```sh
deno task probe
```

Its temporary task compiles the frozen Core sources with `HistoryProbe.swift`, then runs the executable. It opens no windows and does not link the native bank service. The controlled bank action only supplies suspension/resumption; document/history logic is production code.

Completed run output:

```text
CONTROL document save/undo/redo: PASS
STATIONARY_PARTICIPANT notes=1 isDirty=true canRedo=false
RANGE_MULTIPLE_SPANS stationaryDuration=20 expected=10
RANGE_NOTES ["0..20", "10..20", "30..40"]
RANGE_HISTORY undoRestoresOriginal=true redoRestoresRecordedState=true
NOTE_END original=channel(status: 128, data0: 60, data1: 64) moved=channel(status: 144, data0: 60, data1: 0) undo=channel(status: 128, data0: 60, data1: 64) redo=channel(status: 144, data0: 60, data1: 0)
PENDING_BANK_UNDO completed=true priority=2 isDirty=false canRedo=true bankReplayCalls=1
NEXT_UNDO priority=2 bankReplayCalls=2
REPRODUCED: an unsaved document edit becomes clean during suspended bank undo; the next Undo skips it and replays the bank again.
```

The diagnostic exits successfully when it observes the specified defects. **That is successful reproduction, not a passing product acceptance gate.** The temporary snapshot/probe is local evidence, not a permanent regression suite or portable CI artifact.

### Commands for the implementer after repairing source and assertions

Registered Swift selectors:

```sh
deno task verify --filter swiftcore --verbose --qt noteEdits documentHistory eventEdits xcmdEdits timeEdits projectSession bankHistory
```

Reference document/identity and coordinator contracts:

```sh
deno task verify --filter editcheck --filter noteidcheck --filter project-identity --filter voicegroupviewcachecheck --verbose
```

Native save/bank integration:

```sh
deno task verify --filter savecheck --filter vgbankcheck --filter vgsavecheck --verbose
```

These commands were checked against registered names/selectors, **not run in this audit**. The voicegroup save lane includes UI behavior; run it under the repository's controlled desktop/offscreen policy, not while competing with user input. Existing green suites alone are insufficient until the missing scenarios and inaccurate mappings above are repaired.

Acceptance evidence must identify the tested revision, exact command, actual assertion locations, and observed outcome. Preserve the C++ reference until the required Swift behaviors and subsequent real-UI cutover are demonstrated. The implementer owns repairs; this report does not claim they have been made.
