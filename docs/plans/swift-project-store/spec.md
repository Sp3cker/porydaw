# Spec — Swift project-store port

## What the seam is

`PdProjectService` (`src/project/swift_project_service.{h,cpp}`) is a narrow
C boundary: a serial `std::thread` worker owns `DecompProject`; six
operations (`open`, `songLabels`, `openSong`, `save`, `bankApply`,
`bankRevert`) plus four lease functions. Every payload is borrowed and copied
eagerly on the Swift side (`ProjectService.swift:471-683`).

**Behind the seam** = everything reachable only through that C ABI. After
the flip, the seam is gone except the lease box.

## Frozen contract

`src/swift/app/ProjectService.swift` public surface — unchanged:

- `open(root:)`, `songLabels()`, `openSong(label:)`, `save(...)`,
  `bankApply(...)`, `bankRevert(...)`, `close()`
- `LoadedSong`, `SaveReceipt`, `AppliedBankEdit`, `BankVoice`,
  `BankSlotView`, `NativeBankLease`, `SongConfig`, `SongSource`
- `ProjectServiceError`: `serviceClosed`, `operationFailed(String)`,
  `bankConflict`
- Error strings verbatim, e.g. `"No playable song named %1."`,
  `"Bank materialization token is spent or unknown."`
- Lease semantics: reuse across shared voicegroups, replace-on-edit,
  old-lease readability, single-shot materialization tokens.

## Architecture after the flip

```
ProjectService (PorydawApp, frozen API)
    └─> ProjectStore (PorydawProject actor, dedicated-thread executor)
          ├─ SongCatalog / SongTable / MidiCfg / SongsMk   (S2)
          ├─ VoicegroupStore → VoicegroupSource (Swift)    (S3)
          │     └─ VoicegroupProjectContext → poryaaaa C loader (modulemap)
          ├─ ProjectFileStore / ProjectIdentity            (S1)
          └─ NativeBankLease → PdBankLease box             (S1, survives)
```

`PorydawProject` = new Swift static library at `src/swift/project/`,
mirroring `src/swift/playback/` build shape. Its `module.modulemap.in`
exposes `voicegroup_loader.h` + `banklease.h`.

## Surviving C++ (the whole of it)

`src/project/banklease.{h,cpp}` (~120L): `VoicegroupLease` +
wrap/discard/borrow verbatim, opaque `PdBankLease` box, C ABI
`pd_bank_lease_adopt`/`release`/`bank_token`/`native`, plus
`borrowVoicegroupLease` (clickcheck). Qt-free, POSIX-free, MSVC-clean.
One C trampoline for `VoicegroupFileIo` callbacks lives here too.

`poryaaaa` stays native via modulemap — the audio engine's floor.

## Verified-dead surface (deleted, not ported)

| Surface | Evidence |
|---|---|
| `synthDefinitions` write path | `swift_project_service.cpp:425` always `{}` → `mapsChanged` always false (`decompproject.cpp:792`) |
| `writeSynthDefinitions`, `ensureSynthDataIncluded`, `reopenedVoicegroupContext`, `pruneStaleBanks` | dead via the above |
| `checkRegistrations`, `applyRegistrationGaps` | `registrationGaps` has no `PdSongMeta` field — never crosses the seam |
| `registerSong`/`makePlan`/`unregister`/`makeRemovalPlan`/`deletableVoicegroup`/`voicegroupArgs`/`removeSongFlags`/`removeRule` | zero live callers; `catalogScan` coupling is inside dead functions (`songregistry.cpp:486,1298`) |
| VoicegroupSource catalog/draft/scalar surface (`catalogScan`, `directSoundSymbols`, `progWaveSymbols`, `synthInstruments`, `typicalAdsr`, keysplit/drumkit catalogs, create/remove voicegroup, include-line mgmt, `voiceDraft`, `applyScalarsToToneData`) | callers are uncompiled (projectio/samplecheck/voicegroupsave/browser) |
| SampleReg, Sidecar, ProjectIo, ProjectWorkspace | uncompiled — no CMake target |
| Widget corpses (mainwindow, workspaceui*, songtab, songsettingsdialog, newsongwizard, sampleeditordialog, voicegroupbrowser, voicegroupviewcache, songlistpanel, transportbar, sampleimport, sf2reader, songdocument, songhistory) | uncompiled; reference deleted headers → delete at the flip |

## Check-porting dispositions

| Suite | Disposition |
|---|---|
| `workspace/*.swift` (session_io, bank_edits, bank_saves, bank_sharing…) | Unchanged — primary flip regression net |
| `proof.identity.txt` (52) | Port A001–A036 → `ProjectIdentityChecks`; drop A037–A052 (history machinery) |
| `proof.mk.txt` | Port behavioral rows → `SongsMkChecks`/`tst_midicfg`; drop fixture guards + DecompProject conjunctions + removeRule tail |
| `proof.save.txt` midi.cfg rows | Port byte-conservation rows → `tst_midicfg` |
| `proof.ioflow`/`iomutations`/`workspace`/`ignore` | Retire — dead transport/dead surface; observable halves already in session suites |
| `proof.voicegroupsourceediting.txt` (98) | Port → `VoicegroupStoreChecks` |
| `proof.savecore.txt` (81) | Port → `VoicegroupStoreChecks` |
| `proof.voicegroupsourcecatalog.txt` | Retire — dead surface |
| `vgbankcheck` (live) | Port 8 cases → `bankleases` suite (Task 26); delete C++ at flip |
| `exportcheck-loop/tail` (live) | Rewrite as Swift suite + native bridge (Task 28); filter names preserved |
| `midienginecheck`, `clickcheck`, audio/playback natives | Untouched — keep passing against the lease shim |

## Threading contract

- `ProjectStore` = actor with a dedicated-thread custom serial executor
  (Foundation `Thread` + mailbox). `readBatch` blocks on file I/O — never
  the cooperative pool.
- `readBatch` fan-out: ≤4 Foundation `Thread`s + `Synchronization.Mutex`
  latch; first-error-wins; soft miss = `found:false` + success; blobs
  malloc'd, freed by the loader via `releaseBatch`.
- `VoicegroupProjectContext` is worker-confined (`@unchecked Sendable`,
  documented single-thread use).

## Platform notes

- Path ops are pure-String with an explicit lexical normalizer replicating
  `QDir::cleanPath` + `VoicegroupId` reject rules; `completeBaseName` =
  `deletingPathExtension().lastPathComponent` (LAST suffix).
- `isAbsolutePath` covers `/`, `X:\`, `X:/`, and `\\` prefixes.
- Path encoding to the C loader: today `toLocal8Bit`; Swift uses UTF-8
  `withCString` — non-ASCII roots on Windows may differ at poryaaaa's
  `fopen`; noted, not fixed here.
