# Task 136 brief — document gesture history retains merge identities across save boundaries

# Context

Complete the existing document Undo/Redo surface for the remaining SongHistory identity cluster. The current historyMergeContracts has semantic examples but not every exact depth/identity conjunct. This is document history only, independent of the bank transition fix.

Selected **16 open rows (0 GAP + 16 PARTIAL)** in `src/checks/project/proof.identity.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A037 | `src/checks/project/identity.cpp:193` — `songHistory_startsClean` |
| A038, A039, A040, A041, A042, A043, A044 | `src/checks/project/identity.cpp:205,206,207,210,211,213,214` — `songHistory_mergePreservesOldestBeforeFreshAfter` |
| A045, A046, A047, A048, A049 | `src/checks/project/identity.cpp:228,229,230,233,234` — `songHistory_savedBoundaryRefusesMerge` |
| A050, A051, A052 | `src/checks/project/identity.cpp:250,251,252` — `songHistory_cancellingMergeRemovesEntry` |

# Exact write set

- `src/swift/core/SongHistory.swift`
- `src/checks/editcheck/NoteHistoryChecks.swift`
- `src/checks/project/proof.identity.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 125 structural remap and 3fbfe933 bank undo. Preserve both; task 132 consumes the saved-state boundary without changing this merge policy. Separate ledger writer applies this identity portion after 135 or in one combined accepted update.

# Interface contract

Keep SongHistory currentIdentity/savedIdentity and HistoryGroup as the only merge owners. A new document starts with equal identities. In the fork-equivalent note move, the two updates merge into one entry, retain oldest value 0 and newest value 3, and Undo/Redo restore their exact identities. A saved boundary refuses the next merge: two entries and value 7; Undo returns to value 3 and its saved identity. A new gesture moved away then back to its origin removes only its own redundant entry, leaving two prior entries, value 7 and the post-boundary identity. Measure relative depth after fixture setup with existing history traversal helpers, and prove complete MIDI bytes after every Undo/Redo. Do not map counts to unrelated bank stack traversal.

# Implementation steps

1. Extend historyMergeContracts and saveIdentity in the existing concept file with the fork numeric sequence, relative depth and exact saved/current identity comparisons.
2. Repair only document merge/seal/cancellation branches in SongHistory if observed behavior diverges; preserve bank action ordering, in-flight gates and remap composition.
3. Exercise the production document API as a scoped runtime smoke using these registered checks; no custom mock history or synthetic Int-only stack.

# Acceptance predicate

The real SongDocument gesture API reproduces depth, values and identities across merge, save boundary, cancellation, Undo and Redo. swiftcore-documenthistory runs the existing historyMergeContracts consumer; saved/reopened UI behavior remains task 132’s responsibility.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-documenthistory --verbose
```

# Task-specific constraints

No BankHistory/API change, no SongDocument/raw-edit write, no test-only history introspection accessor. Identity A001–A036 remain outside this task. Native songhistory remains blocked by other identity/viewcache/automation and transitive SongDocument consumers. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
