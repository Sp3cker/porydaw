# Task 242 brief — SoundFont zones: SF2 reader, zone extraction and the zone-picker model

# Context

Spec.md: "SoundFont import includes searchable preset/instrument/zone selection,
pitch/root/fine-correction conversion, loop-bound conversion, unsupported/ROM-zone refusals
and linked-stereo warning behavior." The fork parsed SF2 in-house (`sf2reader.cpp`, no
library) and chose a zone in `Sf2ZonePicker` before the ordinary editor pipeline. This task
ports the reader, zone extraction and the picker's grouping/filter/selection behavior as a
pure model. The QML zone-picker dialog mounts in 254, which consumes this model.

Surface: SoundFont zone selection → `ImportedSample` (SA02).
Ledger spec: `src/checks/samplecheck/proof.soundfont.txt` (all 34 rows).
Verify lane: `samplecheck`.
Rows: A001–A017, A019–A021 GAP → MATCHED; A024–A033 NATIVE → MATCHED (model predicates);
A022 NATIVE and A023 GAP → RETIRED-REPRESENTATION (widget/objectName and
`QDialogButtonBox::Ok` lookups: "QWidget object lookup; the zone picker is a Swift model plus
a QML dialog"). Blocked rows left untouched: A018 (zone 0 through the render pipeline; 244
closes it) and A034 (OK accepts through the mounted dialog; 254).
Visual `proof.dialogs.txt` Sf2ZonePicker baseline row stays excluded (frozen baselines).

Oracles: `git show fceecd88:src/audio/sf2reader.{h,cpp}` (`Sf2Zone`, `Sf2File`, `sf2Magic`
47, `readSf2Bytes` 52–181, `readSf2File` 183, `extractSf2Zone` 191–236),
`src/ui/sf2zonepicker.cpp` 55–108 (`rebuild`, `updateSelection`), `docs/old/sample-editor/
FORMATS.md` §5. Check oracle: `git show fceecd88:src/checks/samplecheck/soundfont.cpp`
(`makeSoundFontFixture` 27–148; methods soundFontExtraction, soundFontRefusals,
soundFontPicker).

# Exact write set

- `src/swift/sample/Sf2Reader.swift` — NEW: `Sf2Zone`, `Sf2File`, `Sf2Reader`.
- `src/swift/sample/CMakeLists.txt` — add the file.
- `src/swift/app/samplestudio/Sf2ZonePickerModel.swift` — NEW (value type; not bridged).
- `src/swift/app/CMakeLists.txt` — add the file to `PorydawApp`'s source list and
  `PorydawSample` to `target_link_libraries(PorydawApp PUBLIC …)`.
- `src/checks/samplecheck/SoundFontChecks.swift` — NEW `runSoundFontChecks` + local
  `soundFontFixture()` port (pool, zones, `romOnlyBytes`).
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledger `proof.soundfont.txt`.

Shared: `src/swift/app/CMakeLists.txt` (hot; 215 and other tracks), `src/swift/sample/
CMakeLists.txt`, the samplecheck runner/CMake (P4 registration order).

# Prerequisites

240 (`ImportedSample`, `SampleImportFailure`, `SampleNames.sanitize`, lane). Parallel with
241/243.

# Interface contract

- `public struct Sf2Zone: Sendable, Equatable` — fork fields (`name`, `start`, `end`
  exclusive, `loopStart`, `loopEndExclusive`, `sampleRate`, `originalPitch` default 60,
  `pitchCorrection`, `sampleType` default 1, `instrument`, `preset`); `frames`,
  `isStereoPair` (type 2 or 4), `hasLoop` (fork predicate).
- `public struct Sf2File: Sendable` — `pool: Data` (16-bit LE), `zones: [Sf2Zone]`,
  `sourcePath`.
- `public enum Sf2Reader`:
  - `static func isSoundFont(_ bytes: Data) -> Bool` (fork `sf2Magic`).
  - `static func read(_ bytes: Data, sourcePath: String) throws(SampleImportFailure) -> Sf2File`
    — fork chunk walk: `LIST` sub-chunks `smpl`, `phdr`(38), `pbag`(4), `pgen`(4), `inst`(22),
    `ibag`(4), `igen`(4), `shdr`(46); overruns refuse with "the SoundFont file is corrupt or
    truncated."; instrument via igen oper 53, preset via pgen oper 41; ROM zones
    (`type & 0x8000`) and degenerate records (end ≤ start, end > pool frames, rate 0, the
    EOS record) are dropped; fork refusal strings for not-a-SoundFont, missing `smpl`, missing
    `shdr`, no importable samples.
  - `static func readFile(path: String) throws(SampleImportFailure) -> Sf2File` ("cannot read
    <path>.").
  - `static func extractZone(_ file: Sf2File, index: Int) throws(SampleImportFailure) ->
    ImportedSample` — fork `extractSf2Zone`: /32768 float, `sourceKind .sf2`, `sourceBits 16`,
    unpitched when `originalPitch > 127` (baseKey 60, `hasPitchMetadata` false), else exact key
    `clamp(orig + corr/100, 0, 127.99)` split into `baseKey`/`fracSemitone`; loop exclusive →
    inclusive relative to the zone start; `suggestedName = SampleNames.sanitize(zone.name)`
    falling back to the file basename; stereo pair → the fork warning "stereo pair — imported
    one channel."; invalid index → "no SoundFont zone selected.".
- `public struct Sf2ZonePickerModel: Equatable` (app module):
  - `init(file: Sf2File)`; `var filter: String` (setting it rebuilds; trimmed,
    case-insensitive match on zone name, instrument or preset).
  - `groups: [Group]` in first-appearance order; `Group.title` = instrument or "(no
    instrument)", plus " — <preset>" when the preset is nonempty; `Group.rows: [Row]` with
    `zoneIndex` and the six column texts of fork `rebuild` (Sample; Key `midiKeyName` +
    signed "¢" correction or "—" when unpitched; "<rate> Hz"; frames; loop "a–b" relative to
    the zone start or "—"; "stereo pair" or "").
  - `selectedZone: Int` (−1 until a zone row is chosen); `mutating func select(zoneIndex:)`,
    `mutating func selectGroup(title:)` (group rows are not pickable: selection becomes −1);
    `canAccept: Bool` (`selectedZone >= 0`); filtering drops a selection that is no longer
    visible (fork `updateSelection` after `rebuild`).
  - `static let columnTitles = ["Sample", "Key", "Rate", "Frames", "Loop", "Notes"]`,
    `static let title = "Import Sample — pick a SoundFont zone"`, `static let searchPlaceholder
    = "Search samples, instruments, presets…"`.

# Implementation steps

1. `Sf2Reader.swift` over `Data` without copying the pool per zone.
2. `Sf2ZonePickerModel.swift` using `PorydawCore.midiKeyName`.
3. `SoundFontChecks.swift`: fixture port (expose `soundFontFixture()` at file scope for 244's
   A018 and 254's staged `.sf2`); soundFontExtraction (A001–A017: magic, three zones with ROM
   dropped, labels via pdta, zone 0 mono 16-bit 400 frames at 22050 with corr −20 → key 68
   frac .8, loop end 299, name `test_tone`, buffer = pool/32768, zone 1 stereo-pair warning,
   zone 2 unpitched), soundFontRefusals (A019–A020: single-stream `SampleImport` refusal of
   sfbk, truncated container, ROM-only file), soundFontPicker model rows (A021, A024–A033).
4. Ledger edits listed in Context.

# Acceptance predicate

The synthesized SoundFont yields the fork's zones, labels, pitch/loop conversion, ROM and
truncation refusals and stereo-pair warning; the picker model groups, filters, arms and
refuses selection exactly as the fork dialog did.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

Gap: A034 and the dialog rendering are proven by 254's mounted journey.

# Task-specific constraints

The model holds no QtBridge state; 254 bridges it. No render/DSP dependency in this task.
