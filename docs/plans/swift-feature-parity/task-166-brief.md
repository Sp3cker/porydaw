# Task 166 brief — repair windowtier_keyboard's dangling S citations

# Context

`src/checks/selectionkey/proof.windowtier_keyboard.txt` carries **20 strict-debt sites
whose `Mapping:` lines cite S-ids that do not exist in the ledger's own site index**
(A-rows cite S018/S019/S023/S027–S049/S063/S094/S096/S111; the index begins at S120).
The ledger preamble records that these predicates are real and executed: the shellwindow
run "executes the shellwindow predicates S018-S036 plus the grip/chrome rows S037-S040
and the parameter-tab/tap rows S041-S060 through the shellwindow entry of
ShellQmlTests.swift". The citations dangle because those site entries were never
written into the index — the debt is missing bookkeeping, not missing proof.

Selected sites (re-derive at freeze): A001, A005, A008, A009, A026, A028, A029, A032,
A033, A037, A040, A043, A046, A058, A059, A087, A095, A098, A109, A112.

The proving predicates live in the ledger's declared counterparts:
`src/checks/selectionkey/localinputtier_text.swift`,
`src/checks/selectionkey/localinputtier_window.swift`, and the shellwindow QML files
(`tst_ShellWindow.qml` and siblings), all of which emit distinctive message literals
and execute under the `shellwindow`/`swiftcore` lanes with evidence artifacts in
`build/proof-evidence/shellwindow*.json` and `swiftcore.json`.

# Exact write set

- `src/checks/selectionkey/proof.windowtier_keyboard.txt` — new S-site entries with message anchors for the dangling citations, and the affected A-row `Mapping:` lines only.

No check-source changes.

# Prerequisites

None. Disjoint from Tasks 158/164/165. Read sprint-3 §19 for shared constraints.

# Interface contract

For each dangling citation: locate the predicate that actually proves the A-row's fork
clause (the fork cite is in the A-row header; the clause text is in its `Original
expression`), verify its distinctive literal resolves in the live source and its row
appears in the executed evidence, then add an S-site entry
(`S<next-id> | <function> | <path>` + `Anchor: message "<literal>"`, `#n` where the
literal repeats) and point the A-row's `Mapping:` at it. Do not renumber existing
S120+ entries. A row whose proving predicate cannot be identified with executed
evidence keeps a written reason and stays debt. Dispositions stay MATCHED.

# Implementation steps

1. Capture the fresh strict inventory (before).
2. Resolve each dangling citation to its executing predicate; add the S entries and
   re-point the mappings.
3. Re-run the shellwindow and swiftcore lanes for fresh evidence; confirm the
   after-inventory delta equals exactly the repaired set.

# Acceptance predicate

No windowtier_keyboard A-row cites a nonexistent S-id; every repaired citation is
message-anchored with executed evidence; the ledger's strict debt falls from 20 to only
unresolved rows with written reasons.

Named checks under §19 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

This is citation repair, not re-derivation from scratch: only predicates the preamble
already credits (shellwindow/localinputtier families) are eligible. No disposition
changes, no check-source edits, no S120+ renumbering.
