# Task 248 brief — Sample commit transaction and loader-context refresh

# Context

The fork's `ProjectIo::commitSample` (`projectio.cpp` 627–655) runs one worker operation:
register or update the sample (fatal on failure), rebuild the voicegroup loader context
(`DecompProject::rebuildVoicegroupProject` 362–380: fresh context, bank caches dropped), then
write or remove the sidecar (non-fatal, reported). The UI then refreshes the catalog and, for a
voice-initiated import, assigns through the ordinary bank edit. In Swift the native
`ProjectContext` parses the global DirectSound map once at open, so without this rebuild a
newly registered symbol never resolves and an edited sample keeps playing stale bytes.
Task 215 confirmed its `ApplicationSession.refreshVoicegroupCatalog()` only rescans and
republishes catalog lists; it does not rebuild `ProjectContext` or drop
`ProjectStore.pickerSamples` — this task owns both, and 253/254 call 215's refresh after it.

Spec obligations (no ledger rows pin them; spec.md "Audition, commit and reopen", SA05/SA06):
new commit = sample + registration + provenance with the fork write order; existing-sample
edit refreshes audio without fabricating a bank edit; shared banks stay coherent (VG05 — the
publication path below is the one `twoOpenSessionsShareBankEdit` proves).

Surface: `ProjectService.commitSample` / `readCommittedSample` (store transaction).
Ledger spec: none (zero ledger edits).
Verify lane: `swiftcore-bankhistory`.

# Exact write set

- `src/swift/project/VoicegroupStore.swift` — `context` becomes `private(set) var`; add
  `rebind(context:) -> [LoadedBankView]`.
- `src/swift/project/ProjectStore+Samples.swift` — NEW: `commitSample`, `readCommittedSample`.
- `src/swift/project/CMakeLists.txt` — add the file.
- `src/swift/app/ProjectService+Samples.swift` — NEW: async service wrappers + publication.
- `src/swift/app/CMakeLists.txt` — add the file (hot; shared with 215/other tracks).
- `src/checks/workspace/sample_commit.swift` — NEW `sampleCommitRefreshChecks`.
- `src/checks/workspace/SessionChecks.swift` — one call line in `runBankHistorySuite`.
- `src/checks/CMakeLists.txt` — register the check file.

# Prerequisites

246 (`SampleRegistrar.register`, `SampleRegistrationError`), 247 (`update`, sidecar IO,
`readCommitted`, `SampleSidecar`).

# Interface contract

- `VoicegroupStore.rebind(context: ProjectContext) -> [LoadedBankView]` — swaps the context
  and re-materializes every record's current bank from its current source (unsaved edits,
  blank-slot tokens, memos and file times preserved) through the new context
  (`loadPreviewedSource(using:)` for edited sources, `context.load` otherwise); returns one
  fresh `LoadedBankView` per record, dirty state unchanged. A record that fails to reload keeps
  its previous bank and is omitted.
- `public struct SampleCommitRequest: Sendable { name: String; wav: Data; sidecar:
  SampleSidecar?; removeSidecar: Bool; update: Bool }` (fork `CommitSampleInput`).
- `public struct SampleCommitReceipt: Sendable { name: String; sidecarSaved: Bool;
  sidecarError: String }` (fork `SampleCommitted`, `committed` implied by returning).
- `ProjectStore.commitSample(_ request: SampleCommitRequest) throws -> (SampleCommitReceipt,
  [ProjectBankLease])` — actor-isolated, fork order: `update` ? `SampleRegistrar.update` :
  `register` (throw its message; "Could not commit <name>." when empty) → open a fresh
  `ProjectContext` for the root (failure throws "Could not refresh the project sample maps.")
  → `voicegroupStore.rebind`, `projectContext` replaced, `pickerSamples = nil`, each returned
  view adopted via `adoptBankLease(view:)` → sidecar write (`removeSidecar` → remove,
  `sidecarSaved = true`); a sidecar write failure is reported in the receipt, never thrown.
- `ProjectStore.readCommittedSample(name: String) throws -> CommittedSample` (247's
  `readCommitted`).
- `ProjectService.commitSample(_:) async throws -> SampleCommitReceipt` — `requireStore()`,
  runs the store op, then publishes every returned lease through the existing
  `publish(appliedBank(lease, token: 0), from: store)` path, so sibling sessions adopt through
  `SharedBankState` with no history entry; `ProjectService.readCommittedSample(name:) async
  throws -> CommittedSample`. Errors surface as `ProjectServiceError.operationFailed(message)`
  (existing `projectFailure` mapping).

# Implementation steps

1. `VoicegroupStore.rebind`.
2. `ProjectStore+Samples.swift`, `ProjectService+Samples.swift`.
3. `sample_commit.swift` (fixture: `stageTestProject` + wav2agb `Makefile`/`audio_rules.mk`
   written into the staged copy): (a) new sample commit → files + `.inc` block + sidecar;
   assigning the new symbol with `applyBankEdit` in session A resolves bytes equal to the
   committed render in A and in peer session B (VG05 coherence for the new symbol); undo of
   the assignment in A leaves the WAV/`.inc` in place; (b) update of an assigned sample →
   both sessions' leases play the new bytes, neither session's undo stack grows, dirty flags
   unchanged, an unsaved edit on the bank survives the rebind; (c) duplicate-name commit
   refuses with the registrar message and publishes nothing; (d) sidecar write failure (a file
   squatting on `.porydaw/samples`) → committed receipt with `sidecarSaved == false` and the
   error text; (e) `pickerSound` after commit returns the new sample (cache dropped).

# Acceptance predicate

A commit registers/updates, rebuilds the loader so the new or edited sample sounds in every
session sharing the bank without a history entry, preserves unsaved bank edits, and reports a
sidecar failure without undoing the committed sample.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-bankhistory --verbose
deno task proof check --executed
```

Gap: the catalog lists (voice-editor sample choices) refresh through 215's API in 253/254,
proven there on the mounted surface.

# Task-specific constraints

No second catalog-refresh path and no `ProjectService.open(root:)` reuse (it resets the bank
views owner). No new history authority: the rebind publication is the existing
`bankViews.publish` path. `VoicegroupStore` stays worker-confined.
