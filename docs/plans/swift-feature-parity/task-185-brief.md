# Task 185 brief — a pending bank transition gates close and bank actions on its origin tab only

# Context

The fork's view cache binds a pending bank transition to its origin tab:
`closeEnabledFor` refuses close only for the pending tab while another tab
stays closable regardless of bank dirt (`voicegroupviewcache.cpp:93-96`), and
resolutions addressed to another identity (`resolveConflict`/`resolveApplied`,
`resolveHardError`) leave `pendingOrigin` set. The Swift gate diverges in a
registered way: `SongTabSession.isDirty = document.isDirty || bankDirty`
(`src/swift/app/SongTabsController.swift:63-66`, rendered by
`SongTabs.qml:185-187`) refuses close on bank-only dirt where the fork closes
the document-clean tab immediately, and Swift drops a queued editor commit when
its origin tab loses selection (`VoiceEditorController.swift:79,99`). These
rows record real unported fork law plus a registered divergence — the task
ports the observable gate and surfaces the divergence explicitly rather than
silently matching either side.

Surface: song-tab close enablement and bank-action enablement while a
voicegroup bank transition is pending — the close affordance the tab strip
renders per tab.
Ledger spec: `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` A046,
A047, A068 (3 GAP), fork `tst_voicegroupviewcache.cpp:278,282,318` at pinned
revision `a7fcaa3e` (`coordinatorRoutesTransitionsAndGates`).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose` and
`deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: viewcache A069 (PARTIAL tail outside this
function), voicegroupsourceediting A086–A092 (retired creation flow, VG03),
voicegroupbank A087–A093 (savecore write-failure family).

# Exact write set

- `src/checks/voicelist/voicelist_session.swift` — origin-gate predicates: a pending transition disables bank actions and close on its origin tab while a document-clean non-origin tab stays closable; resolutions addressed to another voicegroup identity leave the pending origin bound; a hard error for another voicegroup leaves it bound.
- `src/checks/workspace/bank_sharing.swift` or `bank_undo_publication.swift` — conditional second host only if the pending-transition fixture already lives there; pick one home per predicate.
- `src/swift/app/SongTabsController.swift` — the origin-aware close gate replacing or composing the bank-dirty refusal (the registered divergence resolves toward the fork: pending transition on this tab refuses close; other tabs' close follows document dirt only — controller scope flag: this is the recorded divergence and needs the controller's sign-off on the deviating clause before implementation locks it).
- `src/swift/app/voicelist/VoiceEditorController.swift` — conditional repair only if the queued-commit origin guard contradicts the ported pending-origin law.
- `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` — A046/A047/A068 only.

# Prerequisites

All write-set files are clean at `0504b68b`. The fork citations and the
registered-divergence text are in the ledger rows themselves — read them fully
before implementing. Read sprint-3 §22.

# Interface contract

The gate is observed through the session's published per-tab state (the same
surface `SongTabs.qml` binds to): close enablement and bank-action enablement
per tab, pending origin identity. Fork law wins on the observable clauses;
where Swift deliberately diverges (the bank-dirty close refusal is a documented
known limitation), the predicate pins the fork behavior and the brief's
controller flag decides — do not silently keep the divergent behavior.

# Implementation steps

1. Port the pending-origin tracking into the session/tab layer so the
   transition's origin tab is identifiable while pending.
2. Gate bank actions and close per the fork law on the origin tab; keep other
   tabs' close following document dirt only.
3. Prove resolutions and hard errors addressed to other identities leave the
   pending origin bound.
4. Close A046/A047/A068 in the same commit, compact form.

# Acceptance predicate

Pending-transition gating is provably origin-scoped and survives
other-identity resolutions and errors, with executed evidence; the registered
divergence is resolved, not preserved silently.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

Controller scope flag: the bank-only-dirty close refusal is a registered
divergence — if the controller rules the Swift behavior stands, close the
affected conjunct as a deliberate-deviation note instead of porting it. No
queued-commit semantics changes beyond the pending-origin law. Do not touch the
savecore-family rows or the VG03 creation rows. Sole wave-22 writer of this
ledger.
