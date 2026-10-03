# Task 176 brief — a pending reload never exposes a partially bound tab

# Context

The fork's SongTab staged-binding pipeline applied MIDI, bank view and voicegroup
binding in observable stages during a reload, and its test asserted each stage's
emissions. The Swift app installs reloads atomically — the replacement workspace is
built completely before it replaces the live tab, and the original stays fully
selectable until the swap — so the fork's intermediate staged states are unreachable
by construction. Under the sprint's unreachable-fork-state ruling, those rows close
as RETIRED-REPRESENTATION with a refusal predicate proving the atomic guard.

Surface: in-place song reload tab binding (the reload path `openTab(restoring:)`
drives; task 163's fixed restore block lives here).
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`
A076–A079 and A081 (5 GAP), fork `tst_mainwindowrouting_lifecycle.cpp:294-308` at
pinned revision `5f768e34` (`applyMidiStage`/`applyBankView`/`applyVoicegroupBound`/
`beginMidiReload` stage observations and the `readinessChanged` emission).
Verify lane: `deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: A080 (view-state store), A085/A086 (failed project
switch retention, project-store classified), A088/A089/A094/A095/A098
(sidecar/reload-gate/view-state settings/reopen readiness — the pending-reload input
gate stays an open user decision), and the fixture guards A042/A055/A072/A082
(task 178's family).

# Exact write set

- `src/checks/workspace/session_io.swift` — one reload-atomicity refusal scenario: through the production reload path, the original tab stays fully bound and selectable while the replacement is pending, and the swap lands complete (no partially applied MIDI/bank/voicegroup state is ever observable on the live tab).
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — A076–A079 and A081 only, closed as RETIRED-REPRESENTATION citing the ruling.

# Prerequisites

Task 163's landed restore fix is consumed unchanged (`ApplicationSession+Tabs.swift`
is not edited). `session_io.swift` and the ledger are clean in `git status`. Read
sprint-3 §21.

# Interface contract

The scenario drives the real reload trigger on a staged two-song fixture (the
existing `session_io.swift` patterns) and observes: pending reload keeps the original
tab's document, bank and selection fully bound; the replacement installs atomically
(ready state publishes once, complete); no intermediate half-bound publication is
observable on the session. Independent literals for the retained state; comparisons
only against pre-reload captures.

# Implementation steps

1. Add the atomicity scenario beside the existing reload/recovery journeys.
2. Close A076–A079 and A081 as RETIRED-REPRESENTATION with one-line reasons naming
   the atomic-installation guard and the ruling, in the same commit. Compact form:
   header + `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

The fork's staged intermediate states are proven unreachable and the atomic reload
guard has executed refusal evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No staged-binding API invention (the ruling's point is the pipeline's absence). No
`session_edit_routing.swift` edits (task 175 owns it), no pending-reload input-gate
claims, no foreign files.
