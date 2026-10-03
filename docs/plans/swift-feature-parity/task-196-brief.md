# Task 196 brief — the voicegroup coordinator and the retired creation flow close their ledgers

# Context

Two voicegroup ledgers sit at "all remaining rows blocked or
representation-only":

- `proof.tst_voicegroupviewcache.txt` has two PARTIALs. A046's residual
  `cache.closeEnabledFor(otherTab)` conjunct is a **user-ruled deviation**
  (the fork permits immediate close of a non-origin tab with bank-only dirt;
  Swift intentionally refuses to protect unsaved edits,
  `SongTabsController.swift:63-66`) plus a `bankActionsEnabled` coordinator
  conjunct. A069's residual (`cache.bankActionsEnabled() &&
  !cache.pendingOrigin()` after `resolveHardError`) is coordinator-internal:
  Swift drops the pending transition task and exposes no gate or
  pending-origin value. Both close as RETIRED-REPRESENTATION with executed
  refusal predicates: after a hard bank failure the next bank action reaches
  the same bank again (S009 already executes this; add the message-anchored
  observation), and the mounted close gate refuses bank-only dirt.
- `proof.voicegroupsourceediting.txt` has seven GAPs (A086–A092), all on the
  retired `createVoicegroup`/`appendIncludeLine`/`SongRegistry::voicegroupArgs`
  creation flow — spec.md:63 lists create/remove voicegroup and include-line
  management as dead surface with zero live callers and no Swift
  counterpart. Each row closes as RETIRED-REPRESENTATION with an executed
  refusal predicate: no production ingress creates a voicegroup file or
  mutates `voice_groups.inc` (the voice list publishes no new-voicegroup
  action; source enumeration is read-only).

Both ledgers reach zero open rows; their C++ sources are uncompiled in all
CMake targets, so the ledgers and sources delete in the same commit.

Surface: the mounted voicegroup bank/coordinator surface — a hard bank
failure frees the transition, and nothing on the voicegroup surfaces creates
a source file.
Ledger spec: `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt`
A046, A069 (2 PARTIAL); `src/checks/voicegroup/proof.
voicegroupsourceediting.txt` A086, A087, A088, A089, A090, A091, A092
(7 GAP), fork `tst_voicegroupviewcache.cpp` (`:278`, `:320`) and
`voicegroupsourceediting.cpp` at their pinned references.
Verify lanes:
`deno task verify --filter swiftcore --verbose` (bank history/undo
publication) and `deno task verify:shell --filter shell-voicegroup --verbose`.
Blocked rows left untouched: voicegroupbank's guard tails and A087–A093
(parked/pending decision), voicegroupsave presentation A032–A037 and
savecore A016–A025 (VG03 create flow + catalog-outage decision — the New
Voicegroup *surface* exclusion stands; this task retires only the already-
dead `createVoicegroup`/`appendIncludeLine` code path's rows).

# Exact write set

- `src/checks/workspace/bank_history_probes.swift` — message-anchored
  predicate for A069: after `resolveHardError` the next bank action on the
  origin tab reaches the same bank (the coordinator gate is observable only
  as the refusal working).
- `src/checks/workspace/bank_undo_publication.swift` — message-anchored
  predicate for A046's surviving conjunct: a pending bank transition on the
  origin tab keeps bank actions refused until completion.
- `src/checks/voicelist/VoiceListChecks.swift` — message-anchored refusal
  predicate for A086–A092: the mounted voice list exposes no creation
  ingress; enumerating sources never writes `voice_groups.inc` or a `.vg`
  file (assert fixture-directory bytes unchanged across the enumeration).
- `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` — both rows
  closed, then delete the ledger and `tst_voicegroupviewcache.cpp`.
- `src/checks/voicegroup/proof.voicegroupsourceediting.txt` — all seven rows
  closed, then delete the ledger and `voicegroupsourceediting.cpp`.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24 and the
pinned ledger references. Confirm before writing: the fork close-gate
conjunct in A046 is the ruled deviation (cite `SongTabsController.swift:63-66`),
and `createVoicegroup`/`appendIncludeLine`/`SongRegistry::voicegroupArgs`
have zero live C++ callers (`spec.md:63` and a source grep) — if any live
caller exists, the affected rows stay GAP and the ledger is not deleted.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections (fixture byte listings are opaque snapshots).
Fork states unreachable in Swift close as RETIRED-REPRESENTATION with
executed refusal predicates; no test-only APIs or ingress.

# Implementation steps

1. Read `tst_voicegroupviewcache.cpp:278,320` and
   `voicegroupsourceediting.cpp` (`:482–546`) at the pinned references for
   the exact conjuncts.
2. Prove the `resolveHardError` refusal in `bank_history_probes.swift`
   (A069) and the pending-transition gate in `bank_undo_publication.swift`
   (A046's non-deviation conjunct); the ruled-deviation conjunct closes
   inside A046's RR entry citing the deviation.
3. Prove the no-creation-ingress refusal in `VoiceListChecks.swift` (fixture
   bytes unchanged; no new-voicegroup action published).
4. Close all nine rows compact in the same commit; delete both ledgers and
   both uncompiled C++ sources.

# Acceptance predicate

A hard bank failure followed by a second attempt reaches the same bank;
voice source enumeration writes nothing. Both ledgers report zero open rows
and are deleted with their C++ sources.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-voicegroup --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of both voicegroup ledgers, `bank_history_probes.swift`,
`bank_undo_publication.swift` and `VoiceListChecks.swift`. The VG03 New
Voicegroup *surface* exclusion (voicegroupsave presentation A032–A037) is
unchanged — this task retires only the dead code-path rows. Do not touch
savecore/bank guard tails or any `Shell*Support.qml` shared file.
