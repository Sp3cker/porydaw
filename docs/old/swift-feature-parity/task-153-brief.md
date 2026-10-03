# Task 153 brief — bare and bank-recipe saves report actual persisted flags and bank identity

# Context

Complete the existing Save consumer's receipt semantics. Task 140 proved legacy sidecar byte preservation, and 132 proved save/reopen/history; neither establishes the selected `flagsWritten` and refreshed-bank identity conjuncts. Extend the same real-file save journey with bare and bank-recipe receipts, keeping the existing save order. Task 149 consumes the compiler boundary independently; this task does not own its import checks.

Selected **16 GAP rows** in `src/checks/project/proof.iomutations.txt`, at `fceecd88:src/checks/project/iomutations.cpp`:

| Target A-ids | Fork assertion-start lines / clause |
|---|---|
| A057–A064 | 414,419,426,427,429,431,432,433 — bare save, song identity and flags written |
| A065–A072 | 439,440,443,444,446,448,449,454 — bank-recipe save, same bank/song, flags, reopen |

Setup-only rows: A057/A058/A072. A059–A061/A065–A068 include old result-count, completion-wait and variant-pointer representation; do not invent `SongSaved`/`LoadedBankView` envelopes. A062/A063/A070's saved-song identity survives as the exact destination and reopened metadata, not an added return field.

# Exact write set

- `src/swift/app/ProjectService+Bank.swift` — `save`/`saveBankStage` only, conditional repair; all bank-edit/catalog methods preserved.
- `src/swift/project/ProjectStore+Save.swift` — `saveSongFlags`/`saveVoicegroup` only, conditional repair.
- `src/checks/workspace/session_save.swift`
- `src/checks/project/proof.iomutations.txt` — A057–A072 only.

# Prerequisites

Accepted/checkpointed 140 and 146 before `session_save.swift` reuse; preserve 131/132/140's complete config, sidecar, history and ordered-save assertions. Task 152 consumes the service edit boundary read-only; no shared writer is granted. Read sprint-3 §17.

# Interface contract

Keep `ProjectService.save(_:bank:) async throws -> SaveReceipt`, `SaveReceipt.flagsWritten`/`bank`, `ProjectStore.saveSongFlags` and `saveVoicegroup` signatures. Save order stays optional bank, MIDI, flags; a failed stage still prevents later stages.

On an isolated project, use the exact `mus_session_test` destination and the existing fixture bank. Produce a real `captureSave()` snapshot after a fixed config change so `flagsNeeded` is true; do not obtain that condition by altering the returned snapshot or adding a test-only flag. Submit it once with `bank: nil` and once with the loaded bank lease, without calling `didSave` between these two service-level stimuli. Each receipt must report `flagsWritten == true`; actual MIDI and midi.cfg bytes must describe the intended song and config, with other song entries unchanged. The bare receipt has no refreshed bank. The recipe receipt contains a clean refreshed view whose source path and section equal the captured pre-save identity. Reopening the exact label through `DocumentSession.open` returns the saved MIDI/config and the same bank source/section. Keep existing sidecar and save-clean-history proof rather than duplicating it.

# Implementation steps

1. Extend the existing save-persistence file with a cohesive receipt branch using a fixed literal config change and independent expected flags/MIDI state. Fail fixture/open/snapshot errors as setup guards.
2. Execute bare and bank-recipe `service.save` on that snapshot, assert the two flags-written predicates separately, and observe the receipt's optional bank plus exact clean bank identity.
3. Read persisted bytes and reopen through the production document path, asserting the intended label/config/MIDI and unchanged other-song flags. Preserve prior sidecar-byte, ordered-failure and history tests.
4. Repair only demonstrated receipt/persistence divergence at the two named save owners; classify the old result envelopes/counts in the same proving change.

# Acceptance predicate

Both save forms report what was actually written, the recipe's refreshed bank keeps its identity and the intended song reopens with the saved data. `SessionChecks.swift::runProjectSessionSuite` calls `sessionSavePersistence`, which owns this real-file journey; the focused lane observes disk/service outcomes rather than a mock receipt.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No `DocumentSession` changes, new envelopes, event ordering, settings routing rewrite or manifest addition. Savecore A016–A026, unknown-synth-save, preview cleanup A073–A076, creation collisions A077–A087 and closed-worker A088–A097 remain outside this consumer. Four files are one semantic-save boundary; the ledger remains open.
