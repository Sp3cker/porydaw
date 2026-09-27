# Task 170 brief — restore missing mappings in nativewindowing

# Context

`src/checks/nativegraphics/proof.tst_nativewindowing.txt` carries **39 strict-debt
sites that are MATCHED with no `Mapping:` line at all** — the same missing-bookkeeping
shape as tasks 168/169, at the largest scale in the wave. The ledger's declared Swift
counterparts are `src/checks/trackheaders/headerfixture.swift`,
`src/checks/trackheaders/trackheadermenu.swift` and
`src/checks/trackheaders/headerinputfixture.swift` (registered in
`src/checks/CMakeLists.txt:193-196`), which emit distinctive message literals
(verified counts: 7/53/7 `message:`/`what:` sites) and execute with evidence rows in
the track-header/shell artifacts under `build/proof-evidence/`.

Selected sites (re-derive at freeze): A004–A029, A037–A042, A044–A046, A048–A052.
These are the MATCHED rows landed by tasks 147–154's consumers (fresh-rig geometry,
window lifecycle, header surface outcomes) whose mappings were never written.

Per-row re-derivation with the task-168 rule: identify the executing predicate from
the fork cite and `Original expression`, write the mapping citing a message-anchored
S-site (existing or new), and leave unresolved rows in debt with written reasons.
The open GAP rows (A055–A078 rendered outcomes, A047 persisted contrast, A002/A008
Win32) are untouched — this task converts only MATCHED bookkeeping.

# Exact write set

- `src/checks/nativegraphics/proof.tst_nativewindowing.txt` — the 39 sites' Mapping lines and any new S entries only.

No check-source changes.

# Prerequisites

None in-wave: this ledger is disjoint from in-flight Task 158 (which owns
`proof.tst_hostadapter.txt`, not this file). Read sprint-3 §19 for shared constraints.

# Interface contract


Same as task-168: new S entries follow the site format with message anchors quoting
verified literals; anchors resolve in live sources and match executed evidence;
dispositions stay MATCHED; unresolved sites keep written reasons.

# Implementation steps

1. Capture the fresh strict inventory (before).
2. Per site: resolve the proving predicate among the track-header/shell counterparts,
   verify literal + evidence, write the mapping.
3. Re-run the covering lane; the after-inventory delta must equal exactly the
   converted set.

# Acceptance predicate

Every converted mapping cites a message-anchored, executing predicate; the ledger's
strict debt falls from 39 to only reasoned residue; the open GAP rows are unchanged.

Named checks under §19 ownership (the track-header suites are invoked by
`SessionChecks.swift:91-92` under the project-session lane; macOS native Qt desktop
required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

No disposition changes, no new predicates, no check-source edits. If a selected
site's proof rides a lane other than the project-session lane named above, record the
exact lane in the report and run it — do not silently narrow coverage. Task 158's
files stay untouched.
