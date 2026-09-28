# Task 202 brief — the bridge probe remounts inside the roll lane and audits the QtBridge contract

# Context

§17 flagged `swiftqtml/proof.tst_swiftqtml.txt` (78 GAP) with "a
prototype-only fixture label is insufficient evidence that every framework
contract is dead — no retirement without a consumer audit." The audit, done
at §25 planning:

- The fixture `src/checks/swiftqtml/BridgeProbe.qml` imports
  `SwiftQtMlCheck 1.0`, a module that no longer exists — the C++ lane was
  deleted at `67544720` and `sqpRegisterProbeTypes` is dead code; nothing
  mounts the fixture.
- The presenter `BridgeProbe`/`BridgeRow` (`BridgeProbeCheck.swift`) is
  still compiled into the `roll_qml_lane` target and its
  `BridgeProbeLifetimeChecks` run from `tst_SwiftRoll.qml`'s
  `cleanupTestCase` — the Swift half is live; only the QML mount is dead.
- The rows cover the real QtBridge contract every mounted surface relies
  on: presenter property binding (`statusText`), `QListModel` row mutation/
  replacement/insert/remove/reset with delegate identity, returned-object
  retention, null selection, and the action log. The replacement surface is
  therefore the mounted probe itself inside the roll QML lane — a surface
  task, not a blanket retirement.

Surface: `BridgeProbe.qml` mounted by a new `tst_SwiftRollBridge.qml` in
the rollqml lane, registered via `RollQmlTests.swift`'s `runSuite`
(`BridgeProbe.registerQmlElement()`; the fixture's import retargets from
the dead `SwiftQtMlCheck 1.0` to `RollQmlCheck 1.0`).

Ledger spec: `src/checks/swiftqtml/proof.tst_swiftqtml.txt` — all 78 GAP
rows A004–A097 (fork `tst_swiftqtml.cpp` at reference `d3ad6b2c`). On zero
open rows the ledger deletes; the C++ source is already deleted (`67544720`).

Rows adjudicate per clause: MATCHED where the mounted probe executes the
fork's observation on the same real bridge path; RETIRED-REPRESENTATION
with an executed refusal predicate where the clause names a
prototype-harness artefact (delegate serial counters, `probeDiagnostics`
QObject-tree dumps, `QQuickView` mount plumbing, captured `qWarning`
streams). The `unsafeAttemptObjectArgumentCall` path stays unproven —
the pinned QtBridge cannot pass objects into slots (the user's task-164
work); rows whose only observation is an object-argument slot invocation
close RR only if the fork's assertion is the harness representation, else
stay GAP with a why-note.

Verify lane: `deno task verify:qml-roll --verbose` (the new suite runs as a
sibling of `swiftroll-window` under the roll lane).

Blocked rows left untouched: none in other ledgers; `BridgeProbeCheck.swift`
may gain harness slots only (it is already a check file — the
"harness-only slots drive the object-taking operations" comment is its
standing contract).

# Exact write set

- `src/checks/rollqml/RollQmlTests.swift` — `BridgeProbe.registerQmlElement()`
  inside `runSuite` beside the existing registrations.
- `src/checks/swiftqtml/BridgeProbe.qml` — import retarget and any
  harness-glue needed to mount under `roll_qml_tests`; no production
  changes.
- `src/checks/rollqml/tst_SwiftRollBridge.qml` — new suite driving the
  mounted probe through the fork's clause list (binding, model mutation,
  delegate reuse/identity, returned/selected object lifetime, null
  selection, action log).
- `src/checks/swiftqtml/BridgeProbeCheck.swift` — only if a missing fixture
  slot is needed for an executed predicate.
- `src/checks/swiftqtml/proof.tst_swiftqtml.txt` — the closed rows; delete
  the file if the wave leaves zero open rows.

# Prerequisites

All write-set files are clean at `432eaaa1`. Read sprint-3 §25, the fork
`tst_swiftqtml.cpp` at `d3ad6b2c` (full clause list — 78 sites across the
binding, model, delegate-identity, lifetime and null-selection cases), and
the `roll_qml_tests` suite-child convention (`RollQmlTests.swift`
`runSuiteChildren`): every `tst_*.qml` under the input dir is a child run.
Confirm `BridgeProbe.qml` mounts under the roll lane's import paths before
planning predicates; if `Repeater`/`QtObject` seams need adjustment, adjust
inside the fixture file only.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; loop bodies with one QVERIFY are one predicate per
iteration. Expectations are independent literals. Refusal predicates execute
on the mounted probe — e.g. a stale selected reference never reactivates a
released presenter, an out-of-range `selectedIndex` yields no row — through
the fixture's real invocations, never test-only APIs. Object-argument slot
calls are excluded from the lane (pinned QtBridge limitation).

# Implementation steps

1. Register `BridgeProbe`, retarget the fixture import, and create
   `tst_SwiftRollBridge.qml` mounting the fixture.
2. Port each fork clause's observation to a mounted predicate (MATCHED) or
   execute the refusal for harness-only conjuncts (RR).
3. Close the 78 rows; delete the ledger if zero open, same commit.

# Acceptance predicate

The mounted BridgeProbe suite executes the fork's clause-level observations
on the live QtBridge path; `proof check` 0 errors and the swiftqtml ledger
reaches zero or carries only rows whose residual is object-argument slots.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the swiftqtml ledger, `RollQmlTests.swift`,
`BridgeProbe.qml`, `BridgeProbeCheck.swift` and the new suite file. Do not
touch `tst_SwiftRoll.qml` or `RollQmlStaging.swift` (existing lifetime
checks stay where they are), any `Shell*Support.qml`, or other rollqml
suites.
