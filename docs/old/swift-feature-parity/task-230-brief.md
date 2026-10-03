# Task 230 brief — the MIDI-import pipeline and the analysis-page wording law

# Context

P2 ports the fork's Import MIDI wizard (ruling 10). The fork's wizard is
`NewSongWizard` in import mode (`fceecd88:src/ui/newsongwizard.{h,cpp}`):
Analysis → Identity → Sound. It depends on three pure pieces that Swift does
not yet provide:

- The song-emission pipeline `NewSongWizard::songFile`
  (`newsongwizard.cpp:637-654`): dedup of redundant same-tick setters
  **before** the optional division rescale to 24, or to 48 under `-X`. A
  rescale failure keeps the source untouched and produces no song.
- The Analysis page's wording law `AnalysisPage::refresh`
  (`newsongwizard.cpp:423-535`): file/limit lines, bold status, the
  track-action notice, the summary, and the polyphony, default-instrument,
  format-0 and controller notices.
- The suggested label `NewSongWizard::buildPages` (`:589-598`) and the
  track-limit clamp (`:429-431`).

`src/swift/core/MidiImport.swift` already ports `analyzeForImport`,
`rescaleDivision`, `removeRedundantSetterEvents`, `playerRoleName` and
`trackCountPhrase`. The two notice texts exist only as `private`
(`concurrencyNotice`, `instrumentFallbackNotice`, `:279-283`), and there is no
pipeline or summary.

This task is a producer. Its consumer is task 232
(`MidiImportWizardState`), which calls every API below. It makes no UI change
and no ledger edits.

Surface: the Import MIDI wizard's Analysis page text and its Finish
emission (mounted by task 233).
Ledger spec (read-only here): `src/checks/onboardcheck/proof.import.txt`
A048–A052, A057–A062, A071, A074–A077 consume these laws. Their rows close
in tasks 233/234 on mounted evidence.
Verify lane: `deno task checks --filter swiftcore-midiimport --verbose`.
Blocked rows left untouched: every row in both ledgers.

# Exact write set

- `src/swift/core/MidiImport.swift`: public additions on `enum MidiImport`.
  Existing APIs keep their signatures.
- `src/swift/app/midiimport/ImportAnalysisSummary.swift` (new): the value
  type that holds the Analysis page wording.
- `src/swift/app/CMakeLists.txt`: add `midiimport/ImportAnalysisSummary.swift`
  to `add_library(PorydawApp …)`. **Shared** with tasks 231/232 and task 215.
- `src/checks/editcheck/MidiImportWizardLawChecks.swift` (new): predicates.
- `src/checks/editcheck/EventChecks.swift`: one call in
  `runMidiImportSuite`.
- `src/checks/CMakeLists.txt`: add the new check file beside
  `editcheck/EventChecks.swift`. **Shared** with tasks 231/232 and task 215.

# Prerequisites

None. Tasks 230 and 231 can run concurrently, but both edit the two CMake
lists. Serialize those edits (see the sprint conflict matrix).

# Interface contract

On `public enum MidiImport` (PorydawCore):

- `static func prepareImportedSong(_ source: MidiFile, rescale: Bool,
  extendedClocks: Bool) throws -> MidiFile`. Copy `source`, apply
  `removeRedundantSetters`, then apply `rescaleDivision(to: extendedClocks ?
  48 : 24)` only when `rescale` is true. It throws the existing
  `MidiImportError` (for example `.tickOverflow`, whose `description` is
  "Tick rescale to division N exceeds 32-bit tick range"). The input value is
  never modified.
- `static func concurrencyNoticeText(peakNotes: Int, sampleNoteLimit: Int)
  -> String` and `static let instrumentFallbackNoticeText: String`. Promote
  the private texts unchanged. `analyze` keeps using them.
- `static func suggestedSongLabel(sourceFileName: String) -> String`
  (`buildPages:589-598`):
  1. Take Qt `completeBaseName`: the name up to its **last** `.`.
  2. Lowercase it.
  3. Replace each run of `[^a-z0-9]+` with `_`.
  4. Strip leading and trailing `_`.
  5. Prepend `mus_` unless the result starts with `mus_` or `se_`.
  Example: "Cool Song.mid" becomes "mus_cool_song".
- `static func trackLimit(playerTrackCount: Int) -> Int` returns
  `TrackLimits.hardwareCapacity` when the count is negative, else
  `min(count, TrackLimits.hardwareCapacity)`.

`public struct ImportAnalysisSummary: Equatable, Sendable` (PorydawApp)
has these stored `String` members: `fileTracks`, `gameTrackLimit`, `status`,
`trackAction`, `summary`, `polyphony`, `defaultInstrument`, `format`,
`controller`. An empty string means the label is hidden (`setNotice`,
`:417-421`). Its initializer is
`init(analysis: ImportAnalysis, trackLimit: Int, wasFormat0: Bool)`, where
`sourceTracks = mappedTracks + droppedTracks`. It ports these fork clauses
verbatim:

- `fileTracks`: "This file has %1." with `trackCountPhrase(sourceTracks)`.
- `gameTrackLimit`: "The maximum number of tracks in the game is %1."
- `status`: lines joined with "\n", rendered bold by QML:
  - "Porydaw will not import %1." with `trackRangeText(mapped+1, sourceTracks)`
    when tracks are dropped.
  - Otherwise, "Porydaw can import this MIDI file." when nothing is dropped
    and nothing is silent.
  - Otherwise, empty.
- `trackAction`: the actions joined with one space (`:450-467`).
- `summary`: the four-way branch at `:469-490`. The `" The game will mute %1."`
  suffix is included.
- `polyphony`: `concurrencyNoticeText` when `peak > sampleNoteLimit`.
- `defaultInstrument`: `instrumentFallbackNoticeText` when any track has notes
  and `notesBeforeProgram`.
- `format`: the format-0 sentence (`:502-505`) when `wasFormat0`.
- `controller`: the not-exported and needs-review sentences (`:506-525`)
  joined with a space. Only XCMD rows can be needs-review.
- `trackRangeText` (`:27-31`): "track %1" when first equals last, otherwise
  "tracks %1 through %2". It is a private helper in the same file.

# Implementation steps

1. Add the four `MidiImport` members. `analyze` must call the promoted texts
   so that the warning and the notice cannot drift.
2. Write `ImportAnalysisSummary` as a pure initializer. It uses no Qt, no
   I/O, and no formatting beyond string interpolation.
3. Write `MidiImportWizardLawChecks.swift` (`runMidiImportWizardLawChecks(_
   report:)`, called from `runMidiImportSuite`). Use the existing fixtures
   `test_midis/external_import.mid` (division 400, two mapped tracks, peak 7)
   and `test_midis/duplicate_setters.mid`. Each predicate has an independent
   literal expectation:
   - The pipeline with rescale gives division 24. Without rescale it gives
     division 400. The duplicate fixture loses exactly the setters that
     `removeRedundantSetters` removes when run alone: the pipeline dedups
     first. With `extendedClocks`, the target is 48.
   - An in-memory division-12 file with a note at `TimeDefaults.maxTick`
     throws `.tickOverflow(48)` under `extendedClocks`, and the source value
     keeps its division and ticks.
   - Suggested labels: "Cool Song.mid" becomes "mus_cool_song",
     "se_door.mid" becomes "se_door", "Mus_Theme.v2.mid" becomes
     "mus_theme_v2", and "__x__.mid" becomes "mus_x".
   - `trackLimit`: -1 gives 16, 1 gives 1, 40 gives 16.
   - Summary for `external_import.mid`:
     - Limit 16: "Porydaw will import all 2 tracks." and status
       "Porydaw can import this MIDI file.".
     - Limit 1: summary "Porydaw will import all 2 tracks, but the game will
       mute track 2.", an empty status, and a trackAction that contains "move
       track 2 above track 1".
     - The polyphony notice starts with "7 notes play at the same time".

# Acceptance predicate

`MidiImport.prepareImportedSong`, the suggested-label law, the track-limit
clamp and `ImportAnalysisSummary` reproduce the fork clauses above, and the
new predicates execute in the swiftcore-midiimport lane. The existing S001–S059
predicates keep passing.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-midiimport --verbose
deno task proof check --executed
```

Coverage: the lane runs the new predicates and the existing
`importAnalysis`/`importTransforms` rows. Gap: rendering is not covered;
tasks 233/234 cover it.

# Task-specific constraints

- `ImportAnalysisSummary` is presentation wording. It stays in the app layer
  and never enters `PorydawCore`.
- Do not change the text of `analyze` warnings, because S017–S019 anchor on
  it.
- Do not add a file-level read/write API to `MidiFile`. Task 231 writes with
  `encoded()` and the existing project file store.
