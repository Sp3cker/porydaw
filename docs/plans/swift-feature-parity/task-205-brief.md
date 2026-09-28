# Task 205 brief — the voicegroup coordinator and the retired creation flow close their ledgers

# Context

Task 196 landed narrower than its §24 brief: S038 proved the origin-scoped
pending-transition refusal, but three residuals remain open:

- `viewcache` A046 (`tst_voicegroupviewcache.cpp:278` at `a7fcaa3e`): the
  coordinator-gate conjunct — `!cache.bankActionsEnabled() &&
  cache.pendingOrigin() == *tab && !cache.closeEnabledFor(*tab) &&
  cache.closeEnabledFor(*otherTab)`. The §24 ledger note already records
  S038 asserting every observable arm except the peer-immediate-close
  conjunct, which is a user-ruled deviation (Swift refuses close on
  bank-only dirt: `SongTabSession.isDirty = document.isDirty ||
  bankDirty`, `SongTabsController.swift:63–66`). The residual conjunct
  adjudicates: the pending-origin/`closeEnabledFor` distribution is either
  proven MATCHED by S038's executed arms (coordinator gate refusal) or RR
  with an executed refusal predicate that a pending transition keeps the
  origin gate closed while the peer stays actionable except on bank dirt —
  the ruled-deviation conjunct stays recorded in the mapping note.
- `viewcache` A069 (`historyTransitionRegressions` residual): coordinator
  state `cache.bankActionsEnabled()`/`!cache.pendingOrigin()` after a hard
  bank failure — Swift ends the in-flight transition by dropping the pending
  task, and no Swift value exposes the coordinator gate. RR with an
  executed refusal predicate on `bank_history_probes.swift`'s real retry
  guard: after the failure a second attempt reaches the same failure (the
  gate cleared) — the existing S009 journey already proves the first arm.
- `voicegroupsourceediting` A086–A092 (`voicegroupsourceediting.cpp` at
  `fbe1015a`, retirement-flagged ledger): the retired
  `createVoicegroup`/`appendIncludeLine` creation flow — spec.md:63 lists
  it as dead surface with zero live callers (`ProjectIo` has no CMake
  target, `VoicegroupSource::createVoicegroup` and the include-line writer
  have no Swift counterpart). All seven GAPs close RETIRED-REPRESENTATION
  with executed refusal predicates on the real Swift voicegroup surface:
  `VoiceListChecks.swift`/the bank history probes already prove the bank
  surface exposes no voicegroup-creation entry — the refusal predicate is
  that a project open/save round trip and bank switch cannot produce a
  `_voicegroup_qtest_copy`-style created voicegroup or grow the
  `voice_groups.inc` hub.

Surface: the mounted voicegroup coordinator (pending bank transition gate)
and the voice list/bank history surface.

Ledger spec: `voicegroup/proof.tst_voicegroupviewcache.txt` A046 residual
conjunct, A069 (2 PARTIAL — closes one fully, records the ruled deviation on
the other); `voicegroup/proof.voicegroupsourceediting.txt` A086–A092
(7 GAP → RETIRED-REPRESENTATION; ledger deletes on zero, C++ source already
deleted at `67544720`).

Verify lanes: `deno task verify --filter swiftcore-projectsession
--verbose` and `--filter swiftcore-bankhistory` (the bank/coordinator probe
hosts); confirm the exact lane that executes `VoiceListChecks` before
writing the acceptance commands.

Blocked rows left untouched: voicegroupbank's label-guard and savecore
tails (identity-ingress surface + savecore decision), voicegroupsave
A032–A037 (VG03 create flow).

# Exact write set

- `src/checks/workspace/bank_history_probes.swift` — the executed retry/
  coordinator-gate refusal for A069.
- `src/checks/workspace/bank_undo_publication.swift` — the executed
  pending-transition gate predicate for A046's residual arm, if it doesn't
  already live there (confirm before editing; S038 may cover it).
- `src/checks/voicelist/VoiceListChecks.swift` — the executed no-creation
  refusal predicates for A086–A092.
- `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` and
  `proof.voicegroupsourceediting.txt` — the closed rows; the sourceediting
  ledger deletes when it reaches zero.

# Prerequisites

Read sprint-3 §25, the fork `coordinatorRoutesTransitionsAndGates` and
history-regression sections at `a7fcaa3e`, and spec.md:63's dead-surface
list at its pinned reference. Confirm what S038 already executes before
adding A046's arm — never re-cite a neighbouring predicate for a distinct
conjunct. Confirm `VoiceListChecks`'s bank round-trip journey executes a
real open/save before writing the refusal.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; expectations are independent literals; refusal
predicates execute on real surface guards. The A046 bank-only-dirt close
refusal is the standing user-ruled deviation — record it in the mapping
note, never assert the fork's permissive behaviour.

# Implementation steps

1. Adjudicate A046's residual arm and A069 on the coordinator probes.
2. Retire A086–A092 with executed refusals on the voice-list surface.
3. Close the rows; delete the sourceediting ledger at zero, same commit.

# Acceptance predicate

The executed coordinator/refusal predicates pass on their lanes;
`proof check` 0 errors; the sourceediting ledger is deleted.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the two voicegroup ledgers and the three check files.
Do not touch voicegroupbank or voicegroupsave ledgers/rows, `SessionChecks`
or any `Shell*Support.qml`. If `bank_undo_publication.swift` turns out to
already execute A046's arm, the predicate stays unmodified and the row
closes on the existing S-entry.
