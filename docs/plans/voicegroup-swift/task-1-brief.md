# T1 — Extract `PorydawVoicegroup` (behavior-preserving module split)

## Context

Every voicegroup file in `src/swift/project/` imports only `Foundation` and
`PorydawProjectNative` (`swift-surface.md` §1). Moving them into a leaf module
cuts the recompile cascade (base: 18.2 s for one semantic edit in
`VoicegroupSource.swift`) and gives T3–T8 a home. Consumers: T3–T9 write new
files in the module; T8 changes its modulemap.

## Exact write set

Create `src/swift/voicegroup/`:
- `CMakeLists.txt`, `module.modulemap.in`
- moved (git mv, content otherwise unchanged except access levels):
  `AsmLine.swift`, `VoiceValues.swift`, `VoicegroupSource.swift`,
  `VoicegroupSource+Create.swift`, `VoiceEdits.swift`, `VoicegroupSave.swift`,
  `SynthCatalog.swift`, `MintedSynths.swift`, `VoicegroupStore.swift`,
  `ProjectContext.swift`, `FileIo.swift`, `ProjectFileStore.swift`
- new by extraction: `VoicegroupId.swift` (the `VoicegroupId` type from
  `ProjectIdentity.swift`), `ProjectBankLease.swift` (the `ProjectBankLease`
  class and the `ToneData.isMintedSynthDescriptor` extension from
  `ProjectStore+Bank.swift`).

Edit: `src/swift/project/CMakeLists.txt`, `src/swift/project/ProjectIdentity.swift`,
`src/swift/project/ProjectStore+Bank.swift`, root `CMakeLists.txt`
(`add_subdirectory` before `src/swift/project`), `src/swift/document/CMakeLists.txt`,
`src/swift/app/CMakeLists.txt`, `src/checks/CMakeLists.txt` (modulemap flag and
link for the project lane), and each Swift file outside the module that names a
moved type (add `import PorydawVoicegroup`; `swift-surface.md` §1 "Outside
consumers" and §2 list them — confirm with `lsp references` per moved public type).

## Prerequisites

None.

## Interface contract

- Module `PorydawVoicegroup`; CMake target `PorydawVoicegroup STATIC`;
  `target_link_libraries(PorydawVoicegroup PUBLIC PorydawCore)` is NOT added — the
  module links nothing Swift. Its modulemap `PorydawVoicegroupNative` exposes
  `@PORYAAAA_DIR@/plugin/voicegroup_loader.h` (unchanged content from the project
  modulemap; T8 narrows it). `PorydawProject` links `PorydawVoicegroup PUBLIC`
  and drops its own modulemap/`configure_file`/include flags.
- Public surface = everything in `swift-surface.md` §2 that crosses the module
  boundary, made `public` (17 symbols: `AsmLine` stays internal if `SynthCatalog`
  moves with it — it does; so `AsmLine` stays internal). Everything that was
  `public` stays `public`. `ProjectFileStore` becomes `public` in the leaf
  module (already is). `VoicegroupId` keeps its declaration verbatim.
- `PorydawProjectNative` module name is removed; `PorydawVoicegroupNative`
  replaces it in every `import`.
- Behavior: none changes. `ProjectStore`, `ProjectService`, checks compile
  unchanged apart from imports.

## Implementation steps

1. Create the module directory, `CMakeLists.txt` modeled on
   `src/swift/project/CMakeLists.txt` (Swift 6, batch mode helper, modulemap
   `configure_file`, `-fmodule-map-file` + plugin include path as
   `PUBLIC` compile options so dependents see the Clang module), `git mv` the
   twelve files, extract `VoicegroupId` and `ProjectBankLease` into their own
   files. Keep file bodies byte-identical except the import line and access
   keywords.
2. Wire dependents: `PorydawProject` → links `PorydawVoicegroup`; remove its
   modulemap and flags. `PorydawDocument`, `PorydawApp`, `PorydawAppPresentation`
   inherit transitively; add explicit `import PorydawVoicegroup` where a moved
   type is named. Root `CMakeLists.txt` `add_subdirectory(src/swift/voicegroup)`
   before `src/swift/project`. `src/checks/CMakeLists.txt`: replace the
   `src/swift/project/module.modulemap` flag with the voicegroup one and add
   `PorydawVoicegroup` to the lane link list.
3. Raise access on the §2 visibility list; nothing else.
4. `lsp diagnostics` on every edited/moved file; `lsp references` on
   `ProjectBankLease`, `VoicegroupId`, `BankHandle`, `VoicegroupStore` to confirm
   every importer got the import.

## Acceptance predicate

Tree builds and existing project checks pass unchanged. Controller runs:

```
deno task build:app
deno task build:checks
deno task checks --filter projectstore
deno task checks:bridge
```

`checks --filter projectstore` covers `VoicegroupStore`, `VoicegroupSource`,
`ProjectContext`, lease accessors, picker info (`swift-surface.md` §9).
`checks:bridge` guards that no QML-facing declaration changed.

## Task-specific constraints

- No semantic edits: no renames, no reordering, no doc-comment rewrites.
- Do not touch `src/checks/projectstore/*.swift` bodies except the import line.
- SHARED_TREE: report `tests: DEFERRED_TO_CONTROLLER`.
