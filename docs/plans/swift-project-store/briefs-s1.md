## Task 1: Extract banklease.{h,cpp} (behavior-neutral C++ refactor)

### Context
Lease-box extraction separates the bank-lease ownership types from voicegroup loading and the Swift project service so later seams can consume a stable box type. Box keeps id/loadName until the flip. Pure C++ verbatim move; no Swift touched. Follows plan.md Global Constraints for verbatim moves.

### Exact write set
- `src/project/banklease.h` (new)
- `src/project/banklease.cpp` (new)
- `src/project/voicegroupsource.h` (delete lines 21-95, add `#include "banklease.h"`)
- `src/project/swift_project_service.cpp` (delete PdBankLease struct ~232-236 + 4 fns 557-577, add include)
- `src/audio/audioengine.h:8` (include swap `project/voicegroupsource.h` -> `project/banklease.h`)
- `src/checks/audio/tst_clicktransport.cpp:14` (include swap, same as above)
- `CMakeLists.txt` (~line 213, add `banklease.cpp` to porydaw_app list)

### Prerequisites
- None. Independent of Tasks 2-5; land first so the C++ graph is stable before Swift scaffolding.

### Interface contract
- `banklease.h` holds verbatim: `VoicegroupLease` class + `wrapVoicegroupLease` x2 + `discardVoicegroup` + `borrowVoicegroupLease` (from `voicegroupsource.h:21-95`, incl. AudioEngine friend + private `borrow()`), kept inline in the header. No ODR or behavior drift.
- `banklease.{h,cpp}` holds verbatim: `struct PdBankLease{id, lease, loadName}` (header) + `pd_bank_lease_release` / `_bank_token` / `_native` / `_identity` (cpp).
- `voicegroupsource.h` retains everything from line 97 (`VgMacro`) on. `swift_project_service.cpp:386,436,502` construction sites (`new PdBankLease{...}`) and `lease->id/lease` uses (515,542,564-576) compile unchanged. Same types, same inline bodies, same C entry-point names/linkage.
- MSVC-clean C++ only, per plan.md Global Constraints.

### Implementation steps
1. Create `src/project/banklease.h` with the verbatim `VoicegroupLease` block from `voicegroupsource.h:21-95` (inline bodies unchanged) plus the `PdBankLease` struct from `swift_project_service.cpp:232-236`.
2. Create `src/project/banklease.cpp` with the verbatim 4 functions from `swift_project_service.cpp:557-577`, including the header.
3. Strip `voicegroupsource.h:21-95`, add the `banklease.h` include; strip the struct + 4 functions from `swift_project_service.cpp`, add the include.
4. Repoint `audioengine.h:8` and `tst_clicktransport.cpp:14` to `project/banklease.h`; if either file uses other `voicegroupsource.h` symbols on inspection, keep both includes rather than cutting.
5. Add `banklease.cpp` to the porydaw_app list in `CMakeLists.txt` (~line 213).

### Acceptance predicate
- Behavior-neutral: build compiles with identical symbols and linkage; no Swift changes in this task.
- NAMED CHECKS:
  - `deno task verify --filter vgbankcheck --verbose` — covers borrow/load paths incl. `borrowVoicegroupLease` via clicktransport rig.
  - `deno task verify --filter exportcheck-loop --verbose` — covers offline exporter `bindEngineVoicegroup` path.
  - `deno task verify --filter clickcheck --verbose` — covers AudioEngine loadSong/updateVoicegroup lease flow.

### Task-specific constraints
- Verbatim move only; no renames, no signature changes, no logic cleanup.
- Aliasing-constructor borrow (old line 93) stays as-is; it is standard C++.
- Only `<memory>`, extern-C `voicegroup_loader.h`, QString/VoicegroupId; no new templates, no Qt removals.

## Task 2: Scaffold PorydawProject Swift module at src/swift/project/

### Context
New Swift module `PorydawProject` owns FileStore (Task 3) and identity (Task 4). Link edges only in this task; S6 performs the single call-edge flip. Follows plan.md Global Constraints.

### Exact write set
- `src/swift/project/CMakeLists.txt` (new, mirrors `src/swift/playback/CMakeLists.txt`)
- `src/swift/project/module.modulemap.in` (new, REQUIRED — S3 imports `voicegroup_loader.h` through it)
- `CMakeLists.txt` (~line 171, `add_subdirectory` after playback)
- `src/swift/app` PorydawApp target wiring: `target_link_libraries PUBLIC PorydawProject` (link edge only)
- `src/checks/CMakeLists.txt` (`swift_core_check` section ~:222, add PorydawProject to PRIVATE links)

### Prerequisites
- None blocking; Task 1 is independent. Tasks 3-4 land their `.swift` files into the directory created here.

### Interface contract
- `add_library(PorydawProject STATIC ...)`, Swift 6, AUTOMOC/UIC/RCC OFF, INTERFACE module dir; no poryaaaa link (pure Foundation).
- `module.modulemap.in` IS shipped (resolved decision overrides the no-modulemap deviation: S3 imports `voicegroup_loader.h` through this module).
- PorydawApp gains a PUBLIC link edge on PorydawProject only; `ProjectService.swift` public surface untouched. `swift_core_check` gains a PRIVATE link so checks can import it. No PorydawCore dependency (FileStore/identity are Foundation-only).

### Implementation steps
1. Create `src/swift/project/CMakeLists.txt` mirroring `src/swift/playback/CMakeLists.txt` for a STATIC Swift 6 library with AUTOMOC/UIC/RCC OFF and the INTERFACE module dir, minus the poryaaaa link.
2. Create `src/swift/project/module.modulemap.in` following the playback/app-audio pattern so S3 can import `voicegroup_loader.h` through it.
3. Add the subdirectory in root `CMakeLists.txt` after playback (~line 171).
4. Add PUBLIC PorydawProject to the PorydawApp link list (link edge only, no call sites).
5. Add PorydawProject to the `swift_core_check` PRIVATE link list.

### Acceptance predicate
- Module graph builds; no existing target renamed; no disturbance to existing suites.
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` — covers regression: module wiring compiles and existing swiftcore suite stays green.

### Task-specific constraints
- Additive only; do not touch `ProjectService.swift` or any call edge (S6 owns the flip).
- File-size discipline: one type family per file (Tasks 3-4), declarations-before-implementation ordering.
- synthDefinitions and registrationGaps paths are dead and never cross this seam; do not add any surface for them here.

## Task 3: ProjectFileStore.swift exact API

### Context
Shared Foundation helper layer every later seam consumes, covering every Qt call in the ported leaf surface: QSaveFile atomic writes, QFile read/write, raw-Data CRLF-preserving line loops, QDir mkpath/cleanPath/isAbsolutePath, QFileInfo completeBaseName/exists. Follows plan.md Global Constraints, including Windows-first-party allowlist.

### Exact write set
- `src/swift/project/ProjectFileStore.swift` (new, only file in this task)

### Prerequisites
- Task 2 module scaffold exists.

### Interface contract
Verbatim contract surface (names, shapes, error strings fixed; bodies implement the Qt semantics noted):

```swift
public enum ProjectFileStoreError: Error, Equatable, Sendable {
    case cannotRead(path: String)
    case cannotWrite(path: String)
}
// localizedDescription MUST render "Cannot read <path>" / "Cannot write <path>"
// to match songsmk.cpp:122,211,262 + SongRegistry strings surfaced to UI.

public enum ProjectFileStore {
    public static func read(_ path: String) throws -> Data
    // QFile ReadOnly; missing/unreadable -> cannotRead
    // (songsmk.cpp:117-125, ex-sidecar 32, samplereg/decompproject reads)

    public static func write(_ path: String, data: Data) throws
    // QFile WriteOnly TRUNCATE, non-atomic — preserves songsmk writeRule/removeRule
    // + writeMidiCfgLine crash semantics
    // (songsmk.cpp:208-218,259-269; songregistry.cpp:1522-1532,1579-1589)

    public static func writeAtomic(_ path: String, data: Data) throws
    // Data.write(.atomic) — ONLY where C++ used QSaveFile
    // (ex-sidecar gitignore sidecar.cpp:45-49; voicegroup/synth/sample writes owned by later seams)

    public static func move(from: String, to: String) throws
    // FileManager.moveItem — fails if dest exists
    // (trash rename projectio.cpp:485-486; pre-check existence for clean cannotWrite)

    public static func remove(_ path: String) throws
    // removeItem; missing file = success
    // (matches QFile::remove / removeRule no-op songsmk.cpp:226-227)

    public static func mkpath(_ path: String) throws
    // createDirectory(intermediateDirectories:true)

    public static func listRecursive(url: URL, ext: String) throws -> [String]
    // enumerator + hasSuffix filter (QDirIterator Subdirectories:
    // songregistry.cpp:1314-1316, voicegroupsource.cpp:439-443,609-613,663-666)

    public static func exists(_ path: String) -> Bool
    // fileExists — covers file AND dir
    // (QFileInfo::exists true for .git-as-file worktree case, ex-sidecar.cpp:25)

    public static func completeBaseName(_ path: String) -> String
    // URL(path).deletingPathExtension().lastPathComponent — LAST suffix only:
    // archive.tar.gz -> archive.tar (consumers projectio.cpp:51, voicegroupsource.cpp:908)

    public static func cleanPath(_ path: String) -> String
    // QDir::cleanPath replica: collapse //, resolve ./ and lexical ../, strip trailing /
    // (projectidentity.cpp:28; songregistry.cpp:1540,1596 midiDir+"/../../..")

    public static func isAbsolutePath(_ path: String) -> Bool
    // hasPrefix("/") OR ^[A-Za-z]:[/\\] OR hasPrefix("\\\\")
    // (QDir::isAbsolutePath, Windows-first-party)

    public static func splitLines(_ data: Data) -> (lines: [Data], endsWithNewline: Bool, crlf: Bool)
    // split on \n, drop post-final empty piece, per-line hadCr chop
    // (songsmk.cpp:127-131,230-233); join(lines,"\n")+trailing \n with \r re-appended (213-216,265-268)
}
```

### Implementation steps
1. Emit the error enum plus the 12 static functions with exactly the signatures above; localizedDescription renders the two fixed strings.
2. Implement `read`/`write` on QFile semantics (`write` is plain truncate, never atomic); `writeAtomic` uses `Data.write(.atomic)` only.
3. Implement `move` (pre-check dest existence for clean cannotWrite), `remove` (missing = success), `mkpath` (intermediateDirectories:true), `listRecursive` (enumerator + hasSuffix), `exists` (file AND dir).
4. Implement `completeBaseName` as `deletingPathExtension().lastPathComponent` (LAST suffix only), `cleanPath` as the lexical QDir replica, `isAbsolutePath` with the three-way prefix rule, `splitLines` as raw-Data split with hadCr chop.
5. Keep UTF-8 handling as `String(decoding:as: UTF8)` on the \r-stripped line; writes are `.utf8` bytes. No `String(contentsOf:)` line iteration anywhere.

### Acceptance predicate
- Every helper matches the Qt semantics cited; direct helper behavior is exercised via consuming suites (Task 5 for identity-adjacent helpers; remainder owned by consuming seams).
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` — covers regression: FileStore compiles into PorydawProject and existing swiftcore suite stays green.

### Task-specific constraints
- R1 (cleanPath empty-string): keep BOTH the isEmpty and `== "."` guards verbatim; Qt `cleanPath("")` return is version-dependent.
- R3 (CRLF): raw Data + manual split everywhere; strip trailing \r before any regex-equivalent handling; NEVER `String(contentsOf:)` line iteration.
- R4 (atomic): `Data.write(.atomic)` failure surfaces as cannotWrite; no fallback framework.
- R2 (regex): S1 introduces no NSRegularExpression; the `\w` Qt-vs-ICU risk transfers with SongsMk to S2.
- Windows allowlist ONLY: `Data.write(.atomic)`, moveItem, removeItem, createDirectory, enumerator/contentsOfDirectory, attributesOfItem, FileHandle, `URL(filePath:)`; NEVER FileManager.replaceItem, CryptoKit, Dispatch, NSString path helpers.
- completeBaseName is LAST-suffix strip; synthDefinitions and registrationGaps paths do not port here.

## Task 4: ProjectIdentity.swift (SongName / VoicegroupId / normalizeSavedRecipe)

### Context
Faithful port of `projectidentity.{h,cpp}` normalization incl. `..`/absolute rejection and the `cleanPath` replica edge cases, on top of Task 3 helpers. Follows plan.md Global Constraints.

### Exact write set
- `src/swift/project/ProjectIdentity.swift` (new, only file in this task)

### Prerequisites
- Tasks 2-3 (module + FileStore `cleanPath` replica).

### Interface contract
- `SongName`: struct, Hashable+Equatable+Sendable; failable `init(_:)` rejecting ONLY empty (projectidentity.cpp:8-13).
- `VoicegroupId`: struct (sourceRelativePath normalized, sectionLabel verbatim), Hashable+Equatable+Sendable; failable `init(sourceRelativePath:sectionLabel:)` = cleanPath then reject ("" OR "." OR ".." OR absolute OR "../"-prefix) (projectidentity.cpp:22-34). Swift Hashable replaces qHash+qHashMulti+VoicegroupIdHash (projectidentity.h:59-61). Section label is NEVER normalized.
- `normalizeSavedRecipe(projectPath:labels:selected:) -> SavedWorkspaceRecipe` (projectidentity.cpp:46-69): drop empties, keep-first-duplicate order-preserving, selected-alone iff ordered empty AND selected non-empty, else fallback to ordered[0]; projectPath passes through verbatim.

### Implementation steps
1. Implement `SongName` with the empty-only rejection.
2. Implement `cleanPath`-then-validate `VoicegroupId` init with the five-way rejection; keep sectionLabel verbatim; derive Hashable structurally.
3. Implement `normalizeSavedRecipe` with drop-empty, keep-first-duplicate, selected-alone/fallback rules verbatim.
4. Pin the cleanPath replica edge cases: "" reject; "/abs/perc.vg" absolute reject; ".." reject; "../escape.vg" reject; "drums/../../escape.vg" lexically "../escape.vg" reject; "." reject; "./" -> "." reject; "./drums//shared/../perc.vg" -> "drums/perc.vg"; "drums/./perc.vg" -> "drums/perc.vg".

### Acceptance predicate
- Normalization matches `projectidentity.cpp` byte-for-byte in behavior; covered by the Task 5 suite porting proof.identity.txt A001-A036.
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` — covers ProjectIdentityChecks suite (A001-A036 ports) staying green.

### Task-specific constraints
- R1: keep BOTH the isEmpty and `== "."` guards verbatim in the VoicegroupId init path.
- Section label NEVER normalized; normalization applies to sourceRelativePath only.
- No regex, no Dispatch, no NSString path helpers; Windows-first-party Foundation only.

## Task 5: Swift checks ProjectIdentityChecks.swift in src/checks/projectstore/

### Context
S1 keeps FileStore+identity only. The old SongsMk Swift port and its proof.mk.txt mapping moved to S2 and are explicitly NOT implemented here. This task ports proof.identity.txt A001-A036 and drops A037-A052, resolving the S005/S006 cppID collision. Follows plan.md Global Constraints.

### Exact write set
- `src/checks/projectstore/ProjectIdentityChecks.swift` (new; NOT `src/checks/project/` — that dir dies at the flip)
- `src/checks/support/corecheck/CoreCheckSupport.swift` (new suite case; file ends at case 11, confirm next free id)
- `src/checks/support/corecheck/native_check.cpp` + `tst_swiftcore.*` (confirm suite enumeration only if suites are whitelisted there)
- `src/checks/CMakeLists.txt` (add the new check file to `swift_core_check` sources)

### Prerequisites
- Tasks 2-4 (module, FileStore, identity).

### Interface contract
- Port A001-A008 SongName accept/reject/roundtrip/equality/hash -> `songName`.
- Port A009 (7 data rows identity.cpp:96-102) VoicegroupId rejections incl. normalizes-to-root -> 7 Swift cases.
- Port A010-A019 normalization (`./drums//shared/../perc.vg`->`drums/perc.vg`), empty-section, kick==sameKick (`drums/./`), kick!=snare, hash equality -> `voicegroupId`.
- Port A020-A036 normalizeSavedRecipe dedup/order/selection/fallbacks/legacy/empty -> `savedRecipe`, each with `report.expect/expectEqual` carrying the ORIGINAL cppID except the collision below.
- Drop A037-A052 (SongHistory/QUndoStack mergeWith/obsolete/count/value/identity) as V-1 implementation-pinning; list every dropped site in the check-file header comment with the V-1 reason.
- Resolve the cppID collision: existing S005/S006 cppIDs in `session_playback.swift:115,122` squat on savedRecipe_selectionFallbacks/legacySingleLabel cppIDs for tempo checks; reassign S1 predicates fresh cppIDs so no two predicates share one cppID (green-run identity contract in CoreCheckSupport.swift:39-44).

### Implementation steps
1. Create `ProjectIdentityChecks.swift` in `src/checks/projectstore/` with `songName`, `voicegroupId`, `savedRecipe` cases covering A001-A036 as mapped above; do not add any SongsMk cases.
2. Add the header comment enumerating dropped A037-A052 with the V-1 reason.
3. Allocate the next free suite case in `CoreCheckSupport.swift` and confirm `native_check.cpp`/`tst_swiftcore.*` need no whitelist change; if they whitelist, add the suite there.
4. Register the file in `src/checks/CMakeLists.txt` `swift_core_check` sources.
5. Assign fresh cppIDs to the colliding S1 predicates so every predicate has a unique cppID.

### Acceptance predicate
- Every ported A-site has a `report.expect/expectEqual` with the original cppID (except the explicitly reassigned collision); dropped sites are header-documented, not silently omitted.
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` — covers the new ProjectIdentityChecks suite plus regression across the existing swiftcore suites.

### Task-specific constraints
- R5 (suite id): confirm the next free case id and any whitelist before wiring; do not assume numbering.
- R6 (cppID collision): two predicates MUST NOT share one cppID; dedupe is mandatory, not optional.
- R1: the A009 rejection rows pin the `""`/`.` guard behavior; keep both guards.
- Checks live in `src/checks/projectstore/` only; do not create `src/checks/project/` files.
