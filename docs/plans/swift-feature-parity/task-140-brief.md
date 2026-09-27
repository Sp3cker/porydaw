# Task 140 brief — legacy sidecar bytes survive bare save, recipe save and reload

# Context

Prove the save-persistence consumer with exact bytes, not the current weak marker: the legacy sidecar at `.porydaw/<label>.json` (unsupported artifact of the old pipeline) is seeded by a literal file write on a copied fixture, then left byte-identical by a bare save, a recipe save and a reload. Swift has no `SongSaved`/`LoadedBankView` result envelope: `DocumentSession.save() async throws` (`DocumentSession.swift:311`) returns void and `ProjectService.save(_:bank:) async throws -> SaveReceipt` (`ProjectService+Bank.swift:135`) returns the receipt directly. The envelope clauses retire as representation; the file bytes are the consumer.

Selected **15 open rows (0 GAP + 15 PARTIAL)** in `src/checks/project/proof.iomutations.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file's line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A027, A028, A029 | `src/checks/project/iomutations.cpp:304,309,314` — open, load and seed setup guards |
| A030, A031, A032, A033 | `src/checks/project/iomutations.cpp:321,322,324,326` — bare save leaves bytes |
| A034, A035, A036, A037, A038 | `src/checks/project/iomutations.cpp:331,332,333,335,337` — recipe save leaves bytes |
| A039, A040, A041 | `src/checks/project/iomutations.cpp:341,343,345` — reload leaves bytes |

# Exact write set

- `src/swift/project/ProjectStore+Save.swift` — conditional, only if a byte divergence is demonstrated.
- `src/checks/workspace/session_save.swift`
- `src/checks/project/proof.iomutations.txt` — separate ledger writer only, selected rows above (`L` shared with 141; disjoint A-rows, one ledger writer serializes).

`shell-songs` is read-only smoke for this task, never a write-set file (shared read-only with Task145).

# Prerequisites

Accepted 131 (byte-exact settings/remove) and 132 (save/reopen/history) save contracts; preserve their flags-routing and history laws. No checked-in fixture edits and no shared bank-lease mutation: all work happens on a copied fixture.

# Interface contract

Keep the real signatures: `DocumentSession.save()`, `ProjectService.save(_:bank:)`, `DocumentSession.open(service:label:)`. Seed path `.porydaw/<label>.json` with the exact compact-JSON bytes of the fork seed (`seedLegacySongJson`: `view` {`pxPerBeat`: 48.0, `selectedTrack`: 2}, `editor` {`laneHeight`: 96}); capture the byte literal from `git show fceecd88:src/checks/project/iomutations.cpp`, never from Swift output. Then through the existing save path: a bank-clean save completes and the sidecar bytes equal the seed literal; a save with the bank lease completes and the bytes still equal the seed; a reopen succeeds and the bytes still equal the seed. A027–A029 stay fail-fast setup guards. Delete the incidental `contains "\"protected\": true"` marker predicate (`session_save.swift` legacy-JSON block) and replace it with the three exact-byte predicates; do not preserve the weak wording check. No view-publication protocol is claimed for the recipe save: success plus unchanged bytes is the consumer.

# Implementation steps

1. Write the literal seed file in-check, save bare / with bank lease / reopen through the real session and service, asserting exact byte equality at all three points; keep every existing 131/132 predicate intact.
2. Repair only a demonstrated byte divergence in the existing save path; invent no result envelope, event bus or observation API.
3. Observe the existing `shell-songs` mounted consumer read-only as smoke; claim no sidecar coverage from it.

# Acceptance predicate

The exact sidecar consumer passes: seed literal in, identical bytes out after each of bare save, recipe save and reload. `swiftcore-projectsession` executes the extended save-persistence checks.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
```

# Task-specific constraints

Only iomutations A027–A041 are writable. Bare/recipe receipt flags and song identity (A057–A072), preview cleanup (A073–A076), creation-collision stray bytes (A077–A087) and closed-transport shutdown (A088+) are sequenced or excluded follow-ons; the last is unavailable-infrastructure, not this surface. No new C++. Read sprint-3 §16 for shared constraints, excluded rows and conditional native retirement.
