# Task 199 brief — tab readiness and reload staging close as retired signal-count representation

# Context

`proof.tst_mainwindowrouting_lifecycle.txt` keeps a PARTIAL cluster whose
residuals all name the same retired representation: the fork's
`SongTab::isReady()` sampled at intermediate native staging steps
(`applyMidiStage`, `applyBankView`, `applyVoicegroupBound`) and
`ready.count()` emissions of the Qt `readinessChanged` signal. Swift's tab
publication is atomic — a tab row appears only once its document, bank and
drawer chrome are installed — so the intermediate states and the signal
counts have no counterpart. The executed predicates already prove the
observable laws (S299/S304–S307: no command-ready row before completion,
chrome installed before publication, first ready tab fully seeded; S312/
S316/S319: pending→ready replacement keeps identity, selection and the
mounted page).

Rows in scope (11 PARTIAL):
- A033/A034 — post-reload `isReady()` staging conjuncts (the mounted lane
  already waits for the rendered grid).
- A041 — the reopened tab's focus/focusedness residual after ready
  publication.
- A046/A047/A051/A052/A053/A054 — fresh-open staging: `!probe.isReady()`
  pre-publication and `ready.count()` emission counts.
- A064/A068/A071 — reload staging: `ready.count()` emissions across the
  pending→ready transition.

Each row adjudicates per clause: where the mounted lanes execute the
observable consequence the row closes MATCHED with a message-anchored
predicate added to the staging checks; where the conjunct is purely the
native signal/intermediate representation it closes
RETIRED-REPRESENTATION with an executed refusal predicate (the mounted
shell never publishes an unready or partially-installed tab row).

Surface: the mounted tab lifecycle — fresh open, reload replacement, and
reopen publication gates.
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
lifecycle.txt` A033, A034, A041, A046, A047, A051, A052, A053, A054, A064,
A068, A071 (11 PARTIAL), fork `tst_mainwindowrouting_lifecycle.cpp:149-816`
at its pinned reference.
Verify lanes:
`deno task verify --filter swiftcore-projectsession --verbose` (tab
readiness checks) and `deno task verify:shell --filter shell-tabs-reload
--verbose`.
Blocked rows left untouched: the lifecycle ledger's `swift-project-store`
GAPs (fixture-open A042/A055/A072/A082, view-state store A080/A095/A099/
A103/A110, sidecar snapshot A088/A094/A109, reload-retention A085/A086,
waitForTabReady A089/A098/A102, native close A106–A108), the sidecar
PARTIALs (A004/A010/A031 and the label-resolution family A043–A045/
A056–A059/A073–A075/A083/A087/A090/A096/A097/A100/A101/A104/A105 — parked
guard tails), pending-reload gate A025, ruled-deviation focus conjuncts —
and every other ledger.

# Exact write set

- `src/checks/workspace/session_view_state.swift` — the executed
  message-anchored staging predicates inside `runTabReadinessChecks`: no
  tab row is visible before full installation, the published row is the
  only readiness observation, and the reload publishes exactly one
  replacement at the same tab identity.
- `src/checks/editorqml/tst_ShellTabsReload.qml` — the mounted refusal
  predicate: during pending reload the shell shows no second tab row and no
  partially-installed page; after replacement the single mounted page is the
  ready one.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`
  — the closed rows only.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24 and the fork
staging sections at the pinned reference (`:149–336` fresh open, `:452–530`
reload, `:612–824` reopen). Confirm `SessionView`'s publication is atomic
(no half-installed row can render) before writing the RR rationale — if a
mounted intermediate state is observable, that clause needs a MATCHED
predicate instead.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections. Fork states unreachable in Swift close as
RETIRED-REPRESENTATION with executed refusal predicates; no test-only APIs
or ingress — the reload lanes drive real mounted reloads.

# Implementation steps

1. Read the fork staging clauses at the pinned reference and classify each
   conjunct: observable publication law (MATCHED) vs native signal/
   intermediate state (RR).
2. Add the message-anchored staging predicates to `runTabReadinessChecks`
   and the mounted refusal predicate to `tst_ShellTabsReload.qml`.
3. Close the eleven rows in the same commit, compact form.

# Acceptance predicate

The mounted reload lane proves no partially-installed tab ever publishes:
pending shows the original page, ready shows exactly one replacement at the
same identity — executed predicates; `proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-reload --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of the lifecycle ledger, `session_view_state.swift` and
`tst_ShellTabsReload.qml`. `tst_ShellTabsDrawer.qml` belongs to no wave-24
write set — if a refusal predicate genuinely needs it, message the
controller first. Do not touch the `swift-project-store` rows, the
pending-reload input gate (A025), the sidecar/label-resolution parked
PARTIALs, or any `Shell*Support.qml` shared file.
