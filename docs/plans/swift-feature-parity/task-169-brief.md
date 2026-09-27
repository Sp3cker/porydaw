# Task 169 brief — restore missing mappings in windowtier_lifetime

# Context

`src/checks/selectionkey/proof.windowtier_lifetime.txt` carries **22 strict-debt sites
that are MATCHED with no `Mapping:` line at all** (same shape as the
mainwindowrouting_native pilot: dispositions were recorded without the proving
bookkeeping). The ledger's declared Swift counterparts —
`src/checks/selectionkey/localinputtier_text.swift`, `src/checks/editorqml/
tst_ShellWindow.qml`, `src/checks/editorqml/tst_ShellTabs.qml` — emit distinctive
message literals and execute under the `shellwindow`, `shell-tabs` and `swiftcore`
lanes with evidence in `build/proof-evidence/shellwindow*.json`,
`shellwindow-cross-tab.json` and `swiftcore.json`.

Selected sites (re-derive at freeze): A006, A007, A010, A013, A014, A019, A020, A021,
A025, A026, A027, A028, A030, A031, A033, A035, A036, A037, A038, A039, A042, A051.

Per-row re-derivation with the task-168 rule: identify the executing predicate from
the fork cite and `Original expression`, write the mapping citing a message-anchored
S-site (existing or new), and leave unresolved rows in debt with written reasons.

# Exact write set

- `src/checks/selectionkey/proof.windowtier_lifetime.txt` — the 22 sites' Mapping lines and any new S entries only.

No check-source changes.

# Prerequisites

None. Disjoint from sibling tasks. Read sprint-3 §19 for shared constraints.

# Interface contract

Same as task-168: new S entries follow the ledger's site format with message anchors
quoting verified literals; anchors resolve in live sources and match executed
evidence; dispositions stay MATCHED; unresolved sites keep written reasons.

# Implementation steps

1. Capture the fresh strict inventory (before).
2. Per site: resolve the proving predicate, verify literal + evidence, write the
   mapping.
3. Re-run the covering lanes; the after-inventory delta must equal exactly the
   converted set.

# Acceptance predicate

Every converted mapping cites a message-anchored, executing predicate; the ledger's
strict debt falls from 22 to only reasoned residue.

Named checks under §19 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

No disposition changes, no new predicates, no check-source edits, no edits to
`proof.windowtier_keyboard.txt` (task-166 owns it). Mounted in-memory song-byte
isolation residue (A054-class PARTIALs) stays PARTIAL.
