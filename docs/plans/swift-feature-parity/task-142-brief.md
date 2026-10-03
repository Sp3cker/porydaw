# Task 142 brief — velocity gesture commit exactness, stale rejection and axis voice context

# Context

Complete the velocity gesture commit surface in the host family: exact commit
accounting, external-edit rejection and presentation voice names. The commit
path already stages previews without advancing revision or history
(`hostVelocityGestureContracts`); what remains open is every exact-value
conjunct (landed/preview/held velocities), the no-op and stale-rejection
sequences with literal revision/history arithmetic, and the axis voice names
that follow the played sample. The native focus/cursor/teardown rows and the
same-pass publication residues around this surface are explicitly out of scope below.

Selected **24 open rows (20 GAP + 4 PARTIAL)** across two ledgers. Citations
are assertion-start lines at `fceecd88`, grouped by fork test. Pin note: the
ledger labels A053–A078's enclosing test `events::sendMouse`; at `fceecd88`
those lines sit inside
`readySongTabVelocityTransactionRetainsHeldAndCommittedContracts`
(`src/checks/host/tst_hostintegration.cpp:260`), which drives the pointer
through inline `sendMouse` calls — the brief cites the enclosing test.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A028 | `src/checks/host/tst_hostintegration.cpp:239` — `velocityEditCommitsOnceInvalidatesAndUndoes` |
| A004 | `src/checks/host/tst_hostintegration.cpp:148` — `twoTabReadySessionWithTwoNoteSeed` |
| A044, A045 | `src/checks/host/tst_hostintegration.cpp:279,280` — `readySongTabVelocityTransactionRetainsHeldAndCommittedContracts` |
| A053, A054 | `src/checks/host/tst_hostintegration.cpp:306,307` — same test |
| A063, A065, A066 | `src/checks/host/tst_hostintegration.cpp:317,319,321` — same test |
| A070, A071, A072, A073, A074, A075, A076, A077, A078 | `src/checks/host/tst_hostintegration.cpp:336,337,340,341,342,343,344,345,346` — same test |
| A013, A015, A016 | `src/checks/host/tst_hostadapter.cpp:101,103,104` — `route101FixtureAttachesHostedVelocityMarker` |
| A164, A165, A168 | `src/checks/host/tst_hostadapter.cpp:602,605,615` — `velocityVoiceRoutingUsesPresentationOnlyForSteadyContext` |

# Exact write set

- `src/checks/host/HostBehaviorChecks.swift` — extend `hostNoteDiscovery`,
  `hostVelocityMarker`, `hostVelocityGestureContracts`; add the stale-rejection
  and axis-voice predicates.
- `src/swift/app/drawer/velocity/VelocityPage.swift` — conditional, only if an
  exact-value clause fails at the gesture commit/preview boundary.
- `src/swift/app/drawer/velocity/VelocityAxis.swift` — conditional, only if the
  axis voice-name mapping fails at its boundary.
- `src/checks/host/proof.tst_hostintegration.txt`, `src/checks/host/proof.tst_hostadapter.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 123 (velocity gesture validity) and 136 (gesture merge identities)
before reusing velocity gesture files; preserve their predicates and messages.
No interface depends on the unselected 120-tick steadiness search (A007) or
the Qt destruction order (A183–A185).

# Interface contract

Preserve `hostTwoNoteSession`, the `drawerVelocityVelocityFixture` gesture
entry points (`pointerPress`/`pointerMove`/`pointerRelease`,
`frozenPreview`, `DocumentSnapshot`, history counts) and the existing S001–S007
messages. New predicates observe, through those production APIs:

- No-op commit: updating every selected note to its current velocity commits
  with no mutation, leaving `revision`, history index, selection and previews
  exactly as before (A044, A045).
- Exact values: seed the two gesture notes to velocities 127 and 64
  via production `setNotesVelocity`, capturing
  all baselines after the seed. The explicit gesture targets and every
  preview/landed/held expectation are the fork-rule literals for those fixed
  seeds (`127 → 1`, `64 → 65`) — written as literals,
  never computed from the fixture notes at runtime (A028, A053, A054, A063).
- Click select: a click press on a node narrows the selection to that one
  note without touching revision, history or bytes; commit and undo preserve
  the restored two-note selection (A065, A066).
- Stale rejection: seed fixed stale/external targets the same way, run the
  fork's begin/update/external-edit/commit sequence, and assert rejection
  with revision advanced exactly once (the external edit), the fork-arithmetic
  history index, the stale note unchanged, the external literal landed, both
  previews cleared and the selection preserved (A070–A078).
- Marker attach: the opened route101 fixture keeps the accepted route101 label
  literal (S029/S092 round-trip, never a fresh read-back); the primary track
  and first-note expectations are derived explicitly by the fork's own scan
  procedure over the staged fixture bytes (first engine track containing
  notes, its front note id) and asserted as exact track/note literals; the
  two-note seed selects exactly two notes (A013, A015, A016, A004).
- Axis voice: the axis map voice name reads `Square 1` at the steady cursor,
  `Noise` after the played sample moves to tick 24, and `Square 1` again after
  the non-following sample at tick 26 (A164, A165, A168).

# Implementation steps

1. Strengthen `hostNoteDiscovery`/`hostVelocityMarker` with the
   message-anchored label/track/selection/size literals from the contract
   above.
2. Seed the fixed gesture velocities through production APIs, capture
   baselines after the seed, and extend the gesture-contracts predicate with
   explicit-target commits asserting the written fork-rule literals.
3. Drive the no-op, click-select, commit/undo and stale-rejection sequences
   through the production gesture APIs with real staged drafts; assert the
   exact revision/history/selection/preview conjuncts above, one
   message-anchored predicate per fork clause.
4. Drive the played-sample sequence (ticks 24/25/26, follow/non-follow as in
   the fork) and assert the three voice-name literals from the fork
   (`Square 1`, `Noise`, `Square 1`).
5. Repair only the named gesture/axis owners if an exact-value clause fails;
   never add a test-only observation seam or a second gesture path.

# Acceptance predicate

Exact commit accounting, stale rejection and axis voice context are proved on
the production gesture path with fixed-seed and fork literals.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
```

# Task-specific constraints

No C++ result enums in Swift contracts; no pixel-capture or
content-build-count conjuncts (the fork's `captureQuickBand`/diagnostics
lines are not selected). All velocity/track/note expectations are fixed-seed
literals or fork literals, never runtime transforms of fixture notes or
Swift output. Leave open: A007 search, A008/A142 playback geometry,
focus/mouse-grabber/cursor rows (A083–A098, A122), cross-tab rows (task 144
scope), mutation/undo/redo event rows A127–A133 (follow-on surface),
teardown A183–A185 and all same-GUI-pass PARTIAL residues. Read sprint-3
§16 for shared constraints, excluded rows and conditional native retirement.
