# Task 207 brief — the mounted tab coordinator proves the hard-error gate release

# Context

`viewcache` A069 (`tst_voicegroupviewcache.cpp:320` at `a7fcaa3e`):
after `cache.resolveHardError` on the origin's own identity the fork
asserts `QVERIFY(cache.bankActionsEnabled() && !cache.pendingOrigin())`
— the coordinator gate releases and no origin stays pending. The
residual claimed no Swift value exposes the coordinator gate — stale:
`SongTabsController.pendingBankTabId` (:318) and `closeEnabled(tabId:)`
(:326) are published production values that the real close gate in
`SongTabs.qml` consumes. `DocumentSession.applyBankEdit`'s `defer`
ends the transition on the failure path, so after an own-identity hard
error `pendingBankTabId == -1`, `closeEnabled(originID) == true`, and
a follow-on `applyBankEdit` succeeds — the re-enabled bank actions.

`bank_undo_publication.swift` already mounts `app.songTabs` with a
two-tab fixture inside `VoicegroupViewCacheTest::
coordinatorRoutesTransitionsAndGates` and proves the in-flight and
foreign-error halves (the foreign-error gate at :175-201). Extend the
same check with the own-identity hard error: begin the origin's
transition, fail an origin `applyBankEdit` hard (stale `expected`
against a moved bank, or the failure stimulus the file already uses),
then assert the release conjunct plus a succeeding second bank action —
one predicate per conjunct with its own literal, MATCHED.

Surface: the mounted `SongTabsController` coordinator gates
(`pendingBankTabId`, `closeEnabled`) plus `DocumentSession.applyBankEdit`
re-entry — all real production surfaces, no test-only reads.

Ledger spec: `voicegroup/proof.tst_voicegroupviewcache.txt` A069
(1 PARTIAL → MATCHED). A046 stays PARTIAL (user-ruled deviation:
Swift refuses close on bank-only dirt; standing exclusion).

Verify lane: the lane that executes `bankUndoPublicationChecks`
(confirm its entry name in `SwiftCoreTests`/the checks registry —
likely `swiftcore` or `swiftcore-bankhistory`).

Blocked rows left untouched: A046 (ruled deviation);
voicegroupsourceediting A086–A092 (VG03 open decision).

# Exact write set

- `src/checks/workspace/bank_undo_publication.swift` — the own-identity
  hard-failure section and its release predicates.
- `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` — the
  closed row only.

# Prerequisites

Read sprint-3 §26, the fork site at `a7fcaa3e:315-330`
(`resolveHardError` context and the target QVERIFY), S009 in
`bank_history_probes.swift` (the existing hard-failure stimulus and
its second-attempt observation — reuse the same stimulus shape), and
`bank_undo_publication.swift:120-201` for the mounted fixture and
`applyBankEdit` failure pattern. Confirm `bankTransitionPending`
clears through `endBankTransition` on the thrown path
(`DocumentSession.swift:347-363`) before writing the release
predicate.

# Interface contract

One predicate per fork clause with its unique complete literal; each
A-id on exactly one predicate; expectations independent of production
projections; real mounted ingress only; fail-closed staging. No new
production properties — `pendingBankTabId`/`closeEnabled` already
exist.

# Implementation steps

1. Extend `bankUndoPublicationChecks` with the origin's own hard
   bank-write failure and the release predicates.
2. Close A069 MATCHED in the viewcache ledger, same commit.

# Acceptance predicate

The mounted probe executes the release predicates; `proof check` 0
errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter bankhistory --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-26 writer of the viewcache ledger and
`bank_undo_publication.swift`. Do not touch the themelayout or
rollcheck ledgers (206/208), `bank_history_probes.swift` (S009's owner
stays as cited), or the sourceediting/bank ledgers.
