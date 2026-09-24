## Task 20: Actor shell + executor
### Context
PorydawProject actor at src/swift/project/ owns all S5 orchestration state (open project, bank leases, edit tokens). This task creates the shell and serial executor so Tasks 21–25 have a place to land; no open/read/bank logic yet.
### Exact write set
- src/swift/project/PorydawProject.swift (new: actor definition, init, executor entry)
- src/swift/project/CMakeLists.txt (new: own target, per resolved decision)
- src/swift/project/modulemap.in (new: required, S3 imports voicegroup_loader.h through it)
### Prerequisites
- S1 pd_bank_lease_adopt symbol declared and linkable.
- S3 VoicegroupSource / MintedSynths Swift types exist (used but not called yet).
- plan.md Global Constraints apply.
### Interface contract
- `actor PorydawProject` with `init(projectRoot: URL, service: ProjectServiceHandle)`; all mutable state isolated to the actor.
- Executor: single serial entry `func run<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T` used by all later pipeline entry points; no re-entrant synchronous access to actor state.
- Module name PorydawProject; CMake target of the same name wired into the Swift build.
### Implementation steps
- Define `actor PorydawProject` holding projectRoot, service handle, lease table, and token table (empty at this task).
- Implement serial `run` executor; all later public methods route through it.
- Add CMakeLists.txt for the PorydawProject target and modulemap.in re-exporting the C++ voicegroup_loader header for S3.
- Conform to plan.md Global Constraints (Windows first-party: no FileManager.replaceItem, no CryptoKit, no Dispatch, no NSString path helpers).
### Acceptance predicate
- PorydawProject actor instantiates and a trivial `run` round-trip returns a value.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-actor --verbose` — covers actor init plus serial executor round-trip.
### Task-specific constraints
- Shell only: MUST NOT add open/read/bank/edit methods; those belong to Tasks 21–25.
- See plan.md Global Constraints for Windows/MSVC rules; no deltas here.

## Task 21: Open pipeline
### Context
Project open path on PorydawProject, ported from the C++ service open minus registration-gap handling. Establishes projectRoot, loads song metas, and prepares lease/token tables for later bank work.
### Exact write set
- src/swift/project/PorydawProject+Open.swift (new: open pipeline)
- src/swift/project/PorydawProject.swift (extend: store opened state)
### Prerequisites
- Task 20 actor shell + executor.
- PdSongMeta shape (has no gaps field — resolved decision).
- plan.md Global Constraints apply.
### Interface contract
- `func open() async throws -> ProjectSnapshot` on PorydawProject, routed through the Task 20 executor.
- completeBaseName is LAST-suffix strip: `deletingPathExtension().lastPathComponent` (resolved decision); used for song identity here.
- No gaps surface anywhere: no `registrationGaps` parameter, field, or return value.
### Implementation steps
- Implement `open()` as scan roots, parse song metas, build snapshot, store opened state on the actor.
- Port the C++ open sequence verbatim except DROP checkRegistrations/applyRegistrationGaps entirely: registrationGaps never cross the seam so those functions do not port and no stub or TODO remains.
- Apply completeBaseName as LAST-suffix strip wherever a display/base name is derived.
### Acceptance predicate
- Opening the standard fixture yields the same song set and snapshot identity as the C++ service, with zero gap-related code paths.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-open --verbose` — covers open pipeline song set and snapshot identity, asserts no registration-gap path.
### Task-specific constraints
- MUST NOT port, stub, or reference checkRegistrations/applyRegistrationGaps; grep for `egistrationGap` in the write set MUST be empty.
- See plan.md Global Constraints; no deltas.

## Task 22: Read models
### Context
Read-only accessors over the opened project snapshot: song list, song meta lookup, and bank descriptor reads. Backs UI and pre-flip parity without touching leases.
### Exact write set
- src/swift/project/PorydawProject+Reads.swift (new: songs, songMeta, bankDescriptors)
### Prerequisites
- Task 20 actor shell.
- Task 21 open pipeline and ProjectSnapshot shape.
- plan.md Global Constraints apply.
### Interface contract
- `func songs() async -> [SongRef]`, `func songMeta(id:) async throws -> PdSongMeta`, `func bankDescriptors() async -> [BankDescriptor]`, all actor-isolated and executor-routed.
- Read models are Swift value types (struct, Sendable); callers receive copies, never interior references.
- completeBaseName rule from Task 21 applies to any name derived here.
### Implementation steps
- Implement the three accessors as pure reads over stored opened state; throw the S1-aligned not-open error when called before `open()`.
- Derive display names with LAST-suffix strip only.
- Keep accessors side-effect free: no lease creation, no file I/O, no memo mutation.
### Acceptance predicate
- Post-open reads return fixture song set, correct per-song metas, and bank descriptors; pre-open reads throw not-open.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-reads --verbose` — covers song list, meta lookup, descriptor read, and pre-open error.
### Task-specific constraints
- MUST NOT create leases or perform I/O; read-only task.
- See plan.md Global Constraints; no deltas.

## Task 23: loadBank
### Context
Bank lease acquisition path: open the bank's VoicegroupSource, poke minted synths, and publish the lease for C++ consumers. First cross-seam caller into S3 Swift and S1 adopt.
### Exact write set
- src/swift/project/PorydawProject+Bank.swift (new: loadBank, lease table insert)
### Prerequisites
- Task 20 actor shell; Task 21 opened state.
- S3 Swift `VoicegroupSource.open` and `MintedSynths` poke API.
- S1 `pd_bank_lease_adopt` publish symbol.
- plan.md Global Constraints apply.
### Interface contract
- `func loadBank(bankId:) async throws -> BankLease` routed through the executor.
- Source opening calls Swift `VoicegroupSource.open` (resolved decision: VoicegroupSource is Swift via S3, not C++).
- Minted-synth handling pokes via S3 `MintedSynths`, never by constructing synth definitions locally.
- Publishing hands the lease to C++ exclusively via S1 `pd_bank_lease_adopt`; no parallel publish path.
### Implementation steps
- Look up the bank descriptor, call Swift `VoicegroupSource.open`, then poke minted synths via S3 `MintedSynths`.
- Insert the resulting materialization (Swift value) into the actor lease table and publish via `pd_bank_lease_adopt`.
- Map open failures to the S1-aligned error domain so the blocker-trick error parity holds.
### Acceptance predicate
- Loading each fixture bank yields an adopted lease whose bytes match the C++ service; double-load returns the same lease; unknown bank throws.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-loadbank --verbose` — covers lease bytes vs C++, lease memoization, unknown-bank error, and adopt publication.
### Task-specific constraints
- MUST call Swift `VoicegroupSource.open`; MUST NOT call the C++ loader directly.
- MUST NOT construct or pass synth definitions; minted-synth path goes through S3 `MintedSynths` only.
- S1 error parity for the blocker trick is a constraint: error domain/codes MUST match S1 so pre-flip comparisons hold; see plan.md Global Constraints.

## Task 24: applyVoicegroupEdit
### Context
In-memory voicegroup edit path against a held lease: voice set, blank-slot materialize/revert, source-bytes restore, and preview render. Token table holds Swift materialization values.
### Exact write set
- src/swift/project/PorydawProject+Edit.swift (new: applyVoicegroupEdit + token table ops)
- src/swift/project/PorydawProject.swift (extend: token table storage)
### Prerequisites
- Task 20 actor shell; Task 23 lease table and materialization value type.
- S3 Swift edit primitives: setVoice, materializeBlankSlot, revertBlankSlotMaterialization, restoreSourceBytes, renderPreview.
- plan.md Global Constraints apply.
### Interface contract
- `func applyVoicegroupEdit(lease: BankLease, edit: VoicegroupEdit) async throws -> EditToken` through the executor; `func preview(token:) async throws -> PreviewPCM` for render.
- All mutations call the S3 Swift primitives (setVoice / materializeBlankSlot / revertBlankSlotMaterialization / restoreSourceBytes / renderPreview); no local reimplementation of voice bytes.
- Token table maps token ID to Swift materialization values (resolved decision), actor-isolated.
### Implementation steps
- Resolve the lease, dispatch the edit enum to the matching S3 Swift primitive, store the resulting Swift materialization value in the token table, and return the token.
- Implement preview as renderPreview over the stored Swift value.
- Keep edits in memory only; persistence belongs to Task 25.
### Acceptance predicate
- Each edit kind (set voice, materialize, revert, restore) plus preview matches C++ byte-for-byte on fixtures; bad token throws.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-edit --verbose` — covers setVoice, blank-slot materialize/revert, restoreSourceBytes, renderPreview, and bad-token error.
### Task-specific constraints
- MUST NOT persist to disk; MUST NOT cross the seam with synth definitions.
- See plan.md Global Constraints for Windows/MSVC rules.

## Task 25: saveVoicegroup
### Context
Persist the edited bank and refresh memos. RESOLVED: synthDefinitions always pass as empty through the seam (swift_project_service.cpp:425 passes {}), so the mapsChanged path is dead: no context reopen, no prune, no synth-definition write.
### Exact write set
- src/swift/project/PorydawProject+Save.swift (new: saveVoicegroup)
- src/swift/project/PorydawProject.swift (extend: memo refresh after save)
### Prerequisites
- Task 24 token table with Swift materialization values.
- Task 23 lease table for post-save reload.
- plan.md Global Constraints apply.
### Interface contract
- `func saveVoicegroup(token: EditToken) async throws -> BankLease` through the executor: persist bytes, reload lease, refresh memo, return the reloaded lease.
- No synth-definition parameter or context-reopen parameter exists on this function.
- Post-save lease is the source of truth; the consumed token is invalidated.
### Implementation steps
- Persist the token's Swift materialization bytes and reload the lease from disk, then refresh the actor memo tables.
- Do NOT port writeSynthDefinitions, ensureSynthDataIncluded, reopenedVoicegroupContext, or pruneStaleBanks; the mapsChanged branch does not exist in Swift.
- Save equals persist plus reload plus memo refresh and nothing else.
### Acceptance predicate
- Saving an edited token persists bytes that reload identically, refreshes memos, invalidates the token, and contains no synth-definition or prune path.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-save --verbose` — covers persist+reload round-trip, memo refresh, token invalidation, and absence of the mapsChanged/prune path.
### Task-specific constraints
- MUST NOT implement or stub writeSynthDefinitions / ensureSynthDataIncluded / reopenedVoicegroupContext / pruneStaleBanks; no-prune is the resolved lease-dangling policy since mapsChanged is dead.
- contentModificationDate granularity is a constraint: filesystems with coarse mtime may not advance the date on rapid save; the memo refresh MUST key on reloaded bytes/size rather than assuming mtime changed.
- See plan.md Global Constraints.

## Task 26: Parity suite
### Context
Pre-flip parity harness proving the Swift PorydawProject matches the C++ ProjectService on open/reads/bank/edit/save before the flip removes the C++ path. Lives with the new Swift checks, not the dying check dir.
### Exact write set
- src/checks/projectstore/bankleases_checks.swift (new: parity driver over ProjectService pre-flip)
- src/checks/projectstore/CMakeLists.txt (new or extend: wire the check target)
### Prerequisites
- Tasks 20–25 implemented.
- C++ ProjectService still present pre-flip for side-by-side driving.
- vgbankcheck row-mapping precedent for byte-compare rows.
- plan.md Global Constraints apply.
### Interface contract
- `bankleases_checks` executable drives Swift PorydawProject and C++ ProjectService over the same fixtures and diffs snapshots, leases, edits, previews, and saves.
- Row mapping follows the vgbankcheck pattern (one row per bank/edit case, byte-compare with named diff on mismatch).
- Checks live in src/checks/projectstore/; src/checks/project/ MUST NOT gain new files (that dir dies at the flip — resolved decision).
### Implementation steps
- Build the driver to open both implementations, compare read models, load every fixture bank, apply each edit kind, render previews, save, and byte-compare at each stage.
- Reuse the vgbankcheck row-mapping shape for output so flip-time triage reads identically.
- Record but do not fix pre-existing C++/Swift divergences outside S5 ownership; file them as parity rows.
### Acceptance predicate
- Parity driver runs green on fixtures pre-flip across open, reads, loadBank, edits, previews, and save.
- NAMED CHECKS:
  - `deno task verify --filter projectstore-parity --verbose` — covers full side-by-side parity (open/reads/bank/edit/save) plus vgbankcheck-style row mapping.
### Task-specific constraints
- Fixture-gap risk R8 is a constraint: the parity fixtures do not cover every production bank shape, so a green suite asserts fixture parity only, not exhaustive production parity; MUST NOT claim wider coverage.
- New checks MUST live in src/checks/projectstore/; adding files under src/checks/project/ is prohibited.
- See plan.md Global Constraints.
