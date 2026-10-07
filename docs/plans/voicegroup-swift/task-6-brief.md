# T6 — `VoicegroupLocator` and `VgVoiceDesc` descriptors

## Context

The one `.inc` tokenizer is `VoicegroupSource.parsedSource`. This task makes
it load-bearing for playback: it must produce per-slot descriptors with the C
line-loop semantics (`native-loader-spec.md` §5) and locate voicegroups and
sub-voicegroups like the C loader (§4). Consumer: T7 (`textProvider`,
`BankBuildInputs.locator`, `build(_:at:)`), T9 (catalog folds onto descriptors).

## Exact write set

- `src/swift/voicegroup/VoicegroupLocator.swift` (new)
- `src/swift/voicegroup/VoiceDescriptor.swift` (new; `VgVoiceDesc`, `VoicegroupText`, `extension VoicegroupSource { descriptors() }`)
- `src/swift/voicegroup/VoicegroupSource.swift` (edit `parsedSource`/helpers only where §5 requires)
- `src/checks/projectstore/VoicegroupLocatorChecks.swift` (new; `runVoicegroupLocatorSuite`)

## Prerequisites

T1. T3's `ProjectLayout` interface (spec.md) — code against it; it lands in the
same phase. If it is absent at your start, declare nothing: import the type and
report `BLOCKED` only if the controller has not landed it by the time you need
to compile-check (you don't compile; `lsp` may show an unresolved type — note it
in `selfReviewFindings`).

## Interface contract

`spec.md` → "T6 — locator and descriptors", verbatim. Semantics:

- `locate(voicegroupArg:)` = §4 `find_voicegroup` order over the layout's
  monolithic files and voicegroup directories (declared-name probe, monolithic
  label probe, file probe with the alias rules). `""` arg means `_dummy` as
  `VoicegroupStore.loadBank` already assumes.
- `locateKeysplitTarget`/`locateDrumsetTarget` = §4 `make_*_voicegroup_name`
  + `find_sub_voicegroup_in_directories` rules.
- `nextIncludedFile(after:)` = §4 `next_included_voicegroup`.
- `descriptors()`: slot advance exactly per the §5 table (valid or malformed
  voice macro → +1; `voice_group` metadata with starting note → jump;
  `cry`/`cry_reverse` → fixed fields; boundary/continuation rules). Every
  `ToneData` field formula and mask from §5 is applied in the descriptor
  (`type` includes ALT/REV bits; `panSweep = pan != 0 ? 0x80|pan : 0`;
  square/noise `wavePointerBits`; cry fixed `key 60, attack 0xFF, sustain 0xFF`).
  `displayName` per §5 `set_voice_display_name` (prefix strip, 47-char cap).
  `continuesIntoIncludedFile` is true when the section ended by boundary with
  `contiguousFill` semantics requiring continuation.

## Implementation steps

1. Read §4, §5 and every cited C line. Diff each rule against
   `parsedSource` (`VoicegroupSource.swift`) and `VoiceMacroSpec.all`
   (`VoiceValues.swift`); list the deviations in your result.
2. Change `parsedSource` only where a deviation changes what slot a line lands
   in or what fields it yields; keep `SourceLine.raw` byte-exact so editing and
   `sourceBytes()` are unaffected. Existing checks `projectstore-editing`,
   `projectstore-values`, `projectstore-context` (loader suite) must still pass
   — the controller runs them.
3. `descriptors()` is a pure fold over `lines[sectionBegin..<sectionEnd]`.
4. `VoicegroupLocator` over `ProjectLayout`, reusing `VoicegroupSource.declarations(in:)`
   for label scans (make it `internal static`, not private, if needed).
5. Checks: on the fixture, `locate("fixture_rich")` → hub-included file path +
   `""`/label per how the hub declares it; `locate("nonexistent")` → nil;
   `locateKeysplitTarget("keysplit_fixture")`/drumset for `fixture_drums_a` resolve
   per §4 naming; `descriptors()` for `fixture_rich` yields the slot layout
   the C loader produces (assert type/key/panSweep/ADSR/symbol/tableSymbol/
   displayName for every written slot — derive expected values by hand from
   the `.inc` and §5, not by running C); `fixture_drums_a` (header `, 36`)
   starts at slot 36; a temp file with a malformed `voice_directsound` line
   still advances the slot; a `cry` line yields the fixed fields.

## Acceptance predicate

Controller registers `projectstore-locator` (argv `voicegroupLocator`) and runs:

```
deno task build:checks
deno task checks --filter projectstore-locator
deno task checks --filter projectstore
```

## Task-specific constraints

- Do not add a second tokenizer; extend `parsedSource`.
- `descriptors()` allocates one `[VgVoiceDesc?]` of 128 and nothing per line
  beyond the `String` fields it must return.
