# Task 165 brief — message-anchor the import, gesture-contract, remap and presentation debt

# Context

Four smaller verified strict-mapping clusters (25 sites) whose existing literal
predicates already execute (verified at planning: literals resolve in the live sources
and their rows appear in the evidence artifacts):

| Ledger | Convertible sites | A-ids | Check host |
|---|---:|---|---|
| `src/checks/onboardcheck/proof.import.txt` | 13 | A001, A013, A017, A018, A020, A021, A042, A080, A081, A086, A088, A090, A091 | `src/checks/editcheck/MidiImportChecks.swift` (importAnalysis/importTransforms/importProjectRoundtrip) |
| `src/checks/automationgesturecheck/proof.contract.txt` | 6 | A033, A035, A037–A040 | `src/checks/automation/domain/` gesture functions |
| `src/checks/rollcheck/proof.remap.txt` | 5 | A003, A015, A028, A041, A055 | `src/checks/rollcheck/remap.swift` |
| `src/checks/rollcheck/proof.presentation.txt` | 1 | A034 | `src/checks/rollcheck/presentation.swift` |

Explicitly left in debt with written reasons (planning-verified no executing literal):
contract A028–A030 (`drawerAutomationLegacySpanRows` emits no matched rows), remap
A016/A029 (insertion/duplication guards are `report.fail` setup text). Do not convert
those.

Conversion rule: cited S-site `Anchor: function` → `Anchor: message "<literal>"`
quoting the exact executed literal, with `#n` occurrence indexes where the literal
repeats in the function.

# Exact write set

- `src/checks/onboardcheck/proof.import.txt` — 13 selected S-anchors only.
- `src/checks/automationgesturecheck/proof.contract.txt` — 6 selected S-anchors only.
- `src/checks/rollcheck/proof.remap.txt` — 5 selected S-anchors only.
- `src/checks/rollcheck/proof.presentation.txt` — 1 selected S-anchor only.

No check-source changes.

# Prerequisites

None. Disjoint from Tasks 158 and 164. Read sprint-3 §19 for shared constraints.

# Interface contract

Anchors resolve against live sources and match executed evidence rows; dispositions
stay unchanged; the before/after `(ledger, A-id)` strict inventory is recorded.

# Implementation steps

1. Capture the fresh strict inventory (before) for the four ledgers.
2. Convert each selected site's anchor to its verified literal with occurrence index.
3. Re-run the covering lanes for fresh evidence and confirm the after-inventory delta
   equals exactly the 25 converted sites.

# Acceptance predicate

The four ledgers' strict debt falls from 33 to the 8 explicitly reasoned sites
(contract A028–A030, remap A016/A029, and any site whose fresh evidence run fails to
show the literal — each with a written reason).

Named checks under §19 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-midiimport --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

No disposition changes, no new predicates, no check-source edits. The import wizard
GAP rows stay untouched — this task touches only MATCHED debt anchors.
