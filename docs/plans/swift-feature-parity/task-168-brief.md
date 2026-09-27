# Task 168 brief — restore missing mappings in mainwindowrouting_native

# Context

`src/checks/mainwindowrouting/proof.tst_mainwindowrouting_native.txt` carries **26
strict-debt sites that are MATCHED with no `Mapping:` line at all** (verified: the
A-row blocks carry `Disposition: MATCHED` and nothing else) — bookkeeping from an
earlier era that never recorded which predicate proves them. The ledger's declared
Swift counterparts (`SessionChecks.swift`, `session_*.swift`, `bank_*.swift`,
`ShellQmlTests.swift`, `tst_ShellWindow.qml`, `tst_ShellTabs.qml`,
`tst_ShellOpenFailure.qml`) emit distinctive message literals and execute under
`swiftcore-projectsession` and the shell lanes with evidence artifacts in
`build/proof-evidence/`.

Selected sites (re-derive at freeze): A002, A004–A019, A021, A023, A024, A026, A028,
A030, A032, A037, A074.

This is per-row re-derivation, bounded like task-146's audit: for each site, identify
from the A-row's fork cite and `Original expression` which existing executing
predicate proves the clause, then write the mapping citing a message-anchored S-site
(existing entry, or a new S entry quoting the verified literal). Rows whose proving
predicate cannot be identified with executed evidence keep a written reason and stay
debt — do not force conversions.

# Exact write set

- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_native.txt` — the 26 sites' Mapping lines and any new S entries only.

No check-source changes.

# Prerequisites

None. Disjoint from sibling tasks (no shared ledgers or files). Read sprint-3 §19 for
shared constraints.

# Interface contract

New S entries follow the ledger's site format (`S<id> | <function> | <path>` +
`Anchor: message "<literal>"`, `#n` for repeats) without renumbering existing entries;
`Mapping:` lines cite them. Every anchor must resolve in the live source and match an
executed evidence row. Dispositions stay MATCHED.

# Implementation steps

1. Capture the fresh strict inventory (before) for this ledger.
2. Per site: read the fork clause, locate the executing predicate with its distinctive
   literal and evidence row, write the mapping (new S entry where none exists).
3. Re-run the covering lanes for fresh evidence; the after-inventory delta must equal
   exactly the converted set, with unresolved rows carrying written reasons.

# Acceptance predicate

Every converted site's mapping cites a message-anchored, executing predicate; the
ledger's strict debt falls from 26 to only reasoned residue.

Named checks under §19 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

No disposition changes, no new predicates, no check-source edits. The foreign-window
cluster (A031–A058) keeps its existing deferral notes; only the 26 selected no-mapping
sites are in scope. Do not touch `tst_ShellWindowFocus.qml`'s message literals
(task-155's landed prefixes) or any sibling ledger.
