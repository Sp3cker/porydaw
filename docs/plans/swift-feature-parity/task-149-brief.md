# Task 149 brief — imported MIDI survives project discovery and real mid2agb compilation

# Context

Complete the file/project consumer of the existing `MidiImport` model. The current `importTransforms` proves an in-memory codec roundtrip, not persisted import discovery or compilation. Extend the same registered MIDI-import suite with the fork's copied-project roundtrip and blank/imported compiler journeys. This is neither the unbuilt import wizard nor P3 WAV export. The opened project and compiler consume the bytes produced by the existing Swift codec and flags writer.

Selected **18 GAP rows** in `src/checks/onboardcheck/proof.import.txt`, at `fceecd88:src/checks/onboardcheck/import.cpp`:

| Target A-ids | Fork assertion-start lines / scenario |
|---|---|
| A079, A082–A085 | 294,301,304,305,308 — project/config/file staging |
| A087, A089, A092–A096 | 313,315,319,324,325,327,328 — persisted repeat, discovery, document load, two engine tracks |
| A097–A102 | 343,346,352,355,357,358 — blank and imported real compiler journeys |

Setup/read guards: A079, A082–A085, A087, A089, A092, A093, A095, A097–A101. These are not independent passing predicates. A094/A096 retain discovered playable-unregistered song and two-track document outcomes; A102 retains actual successful compilation. Existing closed A080/A081/A086/A088/A090/A091 remain preservation obligations, including division 24 and byte-identical serialization.

# Exact write set

- `src/swift/core/MidiImport.swift` — `rescaleDivision` only, conditional repair.
- `src/swift/core/MidiFile.swift` — `decode`/`encoded` only, conditional repair.
- `src/swift/project/MidiCfg.swift` — `writeMidiCfgLine` only, conditional repair.
- `src/checks/editcheck/MidiImportChecks.swift`
- `src/checks/editcheck/EventChecks.swift` — call the new cohesive project-roundtrip helper from `runMidiImportSuite` only.
- `src/checks/onboardcheck/proof.import.txt` — selected rows only.

# Prerequisites

Existing `swiftcore-midiimport` model suite, the project-store open/metadata API, and the landed `pdc_check_compile_saved_midi` test boundary used by `session_save.swift`. Task 148's custom-budget case is independent; use the established fixture flags/budget API without waiting for or editing its owner. Read sprint-3 §17.

# Interface contract

Preserve `MidiImport.rescaleDivision(_:to:)`, `MidiFile.decode(_:)`/`encoded()`, `MidiCfg.writeMidiCfgLine(midiDir:label:flags:)`, `ProjectStore.open()`/`songMeta(label:)` and `SongDocument.init(file:config:source:trackBudget:)`. Add one cohesive `importProjectRoundtrip(_:)` check helper in the existing MIDI-import file and invoke it from the suite, using the existing `MainActor.assumeIsolated` harness convention for document construction.

Read staged `test_midis/external_import.mid`, rescale to division 24, persist `mus_onboardcheck_import.mid` and its valid fixture-derived flags in a copied project, reread and serialize to a repeat file. Compare full file bytes; the repeat must equal the first serialized bytes, with division 24 and the same complete events. A real `ProjectStore.open()` must discover the named song as playable, with MIDI/config paths and flags intact, but not registered in the song table. Construct the real document from those persisted metadata/bytes and require exactly two engine tracks.

For both `mus_onboardcheck_compile_blank` and `mus_onboardcheck_compile_imported`, write MIDI/flags and register those two compiler-only labels through the existing `SongRegistration.register` API before calling `pdc_check_compile_saved_midi(projectRoot,songLabel)` from `PorydawCoreCheckNative`: that helper intentionally discovers only song-table entries. Keep the separate roundtrip label unregistered. Require success code 1 for each compiler variant; the existing seam rereads persisted flags, requires mid2agb normal exit/status 0 and reads the resulting assembly. Blank-song literals at `fceecd88:src/project/songregistry.cpp:1603–1636` are format 1, division 24, two chunks ending at tick 96: sequence tempo 500000 and 4/4 bytes `[4,2,24,8]` at tick 0; channel-0 program 0 and CC7 value 100 at tick 0. Do not add another process wrapper or claim success from file existence alone.

# Implementation steps

1. Extend `MidiImportChecks.swift` with the copied-project persisted roundtrip, using `withTempProjectCopy`/`awaitValue` and the actual core/project modules. Setup failures terminate the scenario.
2. Assert discovered metadata and the loaded document's two-track outcome from the on-disk import; preserve the existing analysis/transforms suite and messages.
3. Exercise the real compiler seam for both blank and imported variants, with independently chosen fixture flags and the fixed labels above.
4. Repair only a demonstrated codec/rescale/flags-writer divergence in the closed write set. Classify setup/envelope rows alongside this proving change; retain all wizard rows unchanged.

# Acceptance predicate

The persisted import is discoverable and playable without registration, roundtrips byte-for-byte at division 24, creates the expected two-track document and compiles through the real mid2agb; the blank variant compiles too. `checkcatalog.cpp` registers `swiftcore-midiimport` with the staged fixture and compiler path, `CoreCheckSupport.swift` case 8 invokes `runMidiImportSuite`, and `EventChecks.swift` invokes the new helper. The compiler executable is a required lane input, not an optional skip.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-midiimport --verbose
deno task proof check --executed
```

# Task-specific constraints

A046–A078 remain GAP: wizard controls, naming, overflow refusal and acceptance require a separate mounted surface; passing the model/file lane does not close them. No new check source/manifest entry, no shell bootstrap changes, no new native glue, no creation API, no WAV export. This six-file exception is one import-to-project/compiler consumer boundary.
