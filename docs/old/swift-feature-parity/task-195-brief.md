# Task 195 brief — the mounted host surfaces close the fixture, grabber and null-timeline tails

# Context

`proof.tst_hostintegration.txt` has five PARTIALs that are all
representation tails left by wave 180–188:

- A003/A004/A007 (fixture-context tails, parked since §22): the fork's
  two-tab ready-session wrapper and the 120-tick steadiness search have no
  Swift counterpart; the hosted content (two seeded notes, two-note
  selection, the playhead's presentation voice) is already executed by
  `hostNoteDiscovery` and `hostPlayheadFollowing`.
- A087/A091 (`quickWindow->mouseGrabberItem()` identity): §22 ruled the
  observable contract proven by 180 (forced ungrab and page switch end the
  pan without mutation; the pan keeps its grab after band focus moves);
  grabber-object identity itself has no QML surface. Per the standing
  unreachable-state ruling these close as RETIRED-REPRESENTATION with
  executed refusal predicates: after the pan ends, no mounted item retains
  an active grab and the next press lands on the band, not a stale grabber.

`proof.tst_hostadapter.txt` keeps A137 PARTIAL: the fork's
`QVERIFY(loopTimeline)` null-build guard. Swift's `PlaybackTimeline.build`
is non-optional — the null state is unreachable — so the row closes as
RETIRED-REPRESENTATION with an executed predicate proving build with loop
markers yields a timeline whose loop fields match the document (S021
already builds it; the residual is the non-null clause itself).

Surface: the mounted velocity/automation drawer hosts and the ruler loop
menu — a pan gesture provably releases its grab and loop markers reach the
playback timeline.
Ledger spec: `src/checks/host/proof.tst_hostintegration.txt` A003, A004,
A007, A087, A091 (5 PARTIAL); `src/checks/host/proof.tst_hostadapter.txt`
A137 (1 PARTIAL), fork `tst_hostintegration.cpp`/`tst_hostadapter.cpp` at
their pinned references.
Verify lanes:
`deno task verify:shell --filter shellwindow-velocity --verbose` and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: hostintegration A162/A174–A185 (real
window-close harness — excluded), hostadapter A079 (centring decision) and
A095 (same-GUI-pass residue — excluded), hostseams (no open rows).

# Exact write set

- `src/checks/host/HostBehaviorChecks.swift` — executed refusal predicates
  for the grabber and fixture tails (the pan ends with no retained grab; the
  seeded two-note host context is observed).
- `src/checks/editorqml/tst_ShellWindowVelocity.qml` — mounted refusal
  predicate for the grab identity: after the drawer pan ends by ungrab or
  page switch, a real pointer press reaches the band item directly (no stale
  grabber steals it).
- `src/checks/rollcheck/ruler_loop_menu.swift` — message-anchored predicate
  that `PlaybackTimeline.build` from a loop-marked document always yields a
  timeline with those loop fields (the non-null guard's observable law).
- `src/checks/host/proof.tst_hostintegration.txt` — the five rows.
- `src/checks/host/proof.tst_hostadapter.txt` — A137 only.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24 and task
180's closure rationale for A087/A091. Confirm `PlaybackTimeline.build`'s
non-optional return before writing the RR rationale for A137; if any
fallible build path exists, the row stays PARTIAL instead.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections. Fork states unreachable in Swift close as
RETIRED-REPRESENTATION with executed refusal predicates; no test-only APIs
or ingress — mounted lanes use real pointer input only.

# Implementation steps

1. Read `tst_hostintegration.cpp` at the pinned reference around the six
   clause sites (`:69`, `:78`, `:113`, `:637`, `:661`) and
   `tst_hostadapter.cpp:500` for the exact conjuncts.
2. Add the executed refusal/contract predicates in `HostBehaviorChecks.swift`
   and `tst_ShellWindowVelocity.qml` covering each clause's observable
   consequence.
3. Add the loop-timeline predicate to `ruler_loop_menu.swift` (A137).
4. Close A003/A004/A007/A087/A091 (RR or MATCHED per clause evidence) and
   A137 (RR, non-optional build), compact form, in the same commit.

# Acceptance predicate

Mounted velocity lane: a completed pan leaves no retained grab — the next
real press reaches the band. Swift core: the loop-marked document's built
timeline carries both loop fields. `proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-velocity --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of both host ledgers, `HostBehaviorChecks.swift`,
`tst_ShellWindowVelocity.qml` and `ruler_loop_menu.swift`. Do not touch the
excluded window-close GAPs, A079/A095, or any `Shell*Support.qml` shared
file. RR closures require executed refusal predicates — a bare
representation claim with no executing predicate is a failed task.
