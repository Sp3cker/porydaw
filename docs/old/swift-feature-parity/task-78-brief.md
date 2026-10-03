# Task 78 brief — blank-slot undo token survives an external source refresh

# Context

User ruling (this session): match the fork. A blank-slot fill stays undoable
after an external tool edits the same voicegroup source and the bank reloads.
The Swift store already rejects an unsafe revert byte-for-byte
(`VoicegroupSource.revertBlankSlotMaterialization`, `src/swift/project/VoiceEdits.swift:56-77`
compares every generated line and the rewritten header); the blanket
`tokens.expire(id:)` on a rebuilt bank (`src/swift/project/VoicegroupStore.swift:141`)
is a second, stricter guard that refuses safe undos. Remove it; the byte check
is the single guard.

1. **Fork law** — `git show fceecd88:src/checks/voicegroupsave/switching.cpp`
   lines 177–266, `VoicegroupSaveTest::blankTokenRebasesAcrossSourceReplacement`:
   fill a blank slot, save; an external writer changes a *different* slot
   (`m_dsSlot` release) in the same source file and saves; switch the song to
   another voicegroup and undo back so the home bank rebinds from disk (clean).
   Then: undo empties the filled slot, keeps the external edit, bank dirty,
   disk bytes unchanged ("blank undo restored stale file bytes instead of
   rebasing its token"); redo re-fills it, keeps the external edit, bank clean,
   disk bytes unchanged ("blank redo did not preserve unrelated refreshed bytes");
   cleanup undo empties it; restore + save returns the file to its original bytes.
2. **Swift today**
   - `VoicegroupStore.loadBank` (`VoicegroupStore.swift:115-146`): unchanged
     mtime → cached; changed mtime → `rebasePreservingEdits` keeps the record
     (tokens survive) when possible; otherwise the bank rebuilds and
     `tokens.expire(id:)` burns every token for that id. `TokenRegistry.expire`
     (`:51-53`) has no other caller.
   - Store check E10 (`src/checks/projectstore/ProjectStoreEditChecks.swift:171-214`)
     pins the burn: "an external byte change to a clean bank reloads it and burns
     its minted tokens". That message pins the retired rule; replace the
     predicate, do not keep the message.
   - Session path: `DocumentSession.swift:338-344` records
     `ServiceBankAction(token:materializedBlank:)`;
     `src/swift/app/ServiceBankHistory.swift` replays undo via
     `ProjectService+Bank.swift:~199` `store.revertBlankSlot`. Verify the
     rebind/undo path actually reaches the store with the original token after a
     rebuilt bank (not a stale lease or an invalidated history entry).
3. **Ledger** — `src/checks/voicegroupsave/proof.switching.txt` A030–A046 are GAP
   (Swift counterpart `src/checks/workspace/bank_switching.swift`,
   `bankSwitchingParity`).

# Exact write set

- `src/swift/project/VoicegroupStore.swift` — delete `tokens.expire(id:)` at the
  rebuild site and the now-dead `TokenRegistry.expire`.
- `src/swift/project/VoiceEdits.swift` — only if the byte check is insufficient
  for a slot-shifting external edit (see contract); otherwise untouched.
- `src/checks/projectstore/ProjectStoreEditChecks.swift` — replace E10's burn
  predicate with the rebase laws below.
- `src/checks/workspace/bank_switching.swift` — session-level port of the fork
  journey (new block inside or beside `bankSwitchingParity`).
- `src/swift/app/ServiceBankHistory.swift`, `src/swift/app/ProjectService+Bank.swift`,
  `src/swift/app/DocumentSession.swift` — only if step 2 shows the session drops
  or mis-leases the token across the rebind.

No new C++, no CMake, no QML, no ledger edits (controller runs the ledger pass).

# Interface contract

- A minted token lives until consumed or the project closes; a bank rebuild no
  longer expires it. Revert applies iff the generated lines and rewritten header
  still match byte for byte at their slots; otherwise `.conflict` and the token
  is consumed (existing single-use rule stays).
- Store predicates (E10 replacement; one per clause, new verbatim messages):
  - external edit of a *different* slot in the same section, bank rebuilt clean:
    revert applies, the external edit survives, the published bank is dirty.
  - external edit of the *filled* slot's line: revert returns conflict and the
    external bytes survive.
  - external edit that inserts or removes a slot line before the filled slot
    (shifting it): revert must not remove the wrong line — conflict, or an exact
    revert of the original generated line; assert which and that no unrelated
    line is lost.
- Session predicates (bank_switching.swift), reuse the fork messages verbatim
  where the clause is the same: "blank slot did not materialize under a
  reversible token", "materialized blank did not save", "external source refresh
  did not rebind cleanly", "reopened source did not contain structural and
  unrelated edits", "blank undo restored stale file bytes instead of rebasing its
  token", "blank redo did not preserve unrelated refreshed bytes", "cleanup blank
  undo did not apply", "restoring unrelated slot did not settle", "cleanup source
  save did not settle", and the final byte-equality clause.
- Real staged fixtures (`sound/voice_groups.inc`, `sound/voicegroups/fixture_alt.inc`
  already used by `bank_switching.swift`); the external writer is a plain file
  write of edited bytes (the fork used `VoicegroupSource`; any byte-exact writer
  is fine), never a store API.

# Acceptance predicate

- RED first: the session undo and the E10 replacement's first clause fail on
  the current tree.
- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (projectstore + bankhistory +
  projectsession suites)
- `deno task verify:shell --filter shell-voicegroup --verbose`

# Task-specific constraints

Swift 6.4 idioms on touched code (`Span`/`InlineArray`/typed throws/strict
concurrency where applicable; no hot-path temporaries). Comments at most 2 lines.
One message-anchored predicate per fork clause. No test-only seams. Workarounds
need approval: stop and report instead.
