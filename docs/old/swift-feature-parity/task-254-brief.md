# Task 254 brief — Voice-initiated New/Edit Sample, SoundFont zone picker dialog, reopen-from-provenance

# Context

SA01/SA05/SA06 finish here. `VoiceEditor.qml:156–173` shows "+" (`vgNewSampleButton`) and
"✎" (`vgEditSampleButton`) beside the sample picker; they call
`VoiceListController.requestNewSample/requestEditSample`, which invoke the unassigned
`onNewSampleRequested`/`onEditSampleRequested` callbacks (`VoiceListController.swift:153–155`,
492–498). This task wires them to 253's workflow, adds the destination-slot assignment,
the SoundFont zone picker window (ruling 10: brand-new QML allowed; fork `Sf2ZonePicker` is
the behavioral/visual reference) and the edit-existing flow over 247/248's provenance.

Fork oracle (`git show fceecd88:src/ui/workspaceui_samples.cpp`): `runImportFlow(slot)`;
`continueImportFlow` SF2 branch (`sf2Magic` → `readSf2Bytes` → `Sf2ZonePicker::exec` →
`extractSf2Zone`, `sf2Zone` recorded in the sidecar) and destination ADSR (slot voice when
not CGB); `runEditSampleFlow` (symbol must start with `DirectSoundWaveData_` else warning
"Edit Sample" "This voice does not reference a project sample."), `continueEditSampleFlow`
(247's `SampleReopen` policy; validator "the sample keeps its registered name (<name>).";
`setEditTarget`; `applyParamsExternal` when from source; commit `update`, sidecar kept with
new params when from source else removed); `handleSampleCommitted` assignment: slot ≥ 0,
tab ready and bank actions enabled → keep the destination voice when its macro is
DirectSound / DirectSound-no-resample / DirectSound-alt, otherwise a new DirectSound voice
(key 60, pan 0, envelope `vgDefaultAdsr(typical, macro, symbol)`); set the symbol; submit as
the ordinary bank edit; reveal the slot; status "Saved <name> - the ROM's .bin recompiles on
the next build" for edits. `sf2zonepicker.cpp` (title, search placeholder, six columns,
720 × 480 at 12 px, OK enabled only on a zone row).

VG05 (verified, not a blocker): a bank edit through `DocumentSession.applyBankEdit`
publishes via `SharedBankState` to every session sharing the bank
(`bank_sharing.swift` `twoOpenSessionsShareBankEdit`, `mountedEditReachesPeerTab`); 248
proves a newly committed symbol resolves in both sessions after the loader rebuild. The
assignment here is that same undoable edit (`VoiceListController.applyVoiceEdit`); undoing
it leaves the registered sample in place.

Surface: VoiceEditor "+"/"✎" → Sample Studio (import with destination / edit existing);
SoundFont zone picker window.
Ledger spec and rows: `proof.soundfont.txt` A034 → MATCHED (OK accepts the picked zone
through the mounted picker; the ledger is deleted if zero open rows remain). No other ledger
rows remain for this surface (spec-only journeys below).
Verify lanes: `shell-sample-studio-voice` (new), `shell-sample-studio`, `shell-voicegroup`.
Blocked rows left untouched: visual `proof.dialogs.txt` Sf2ZonePicker/sample-editor baseline
rows (standing exclusion).

# Exact write set

- `src/swift/app/samplestudio/SampleStudioWorkflow.swift` — slot route, edit route, SF2 branch,
  assignment (253's file).
- `src/swift/app/samplestudio/Sf2ZonePickerPresenter.swift` — NEW `@QtBridgeable` wrapper of
  `Sf2ZonePickerModel` (flattened rows as `QListModel<Sf2ZonePickerRow>`, the
  `SongTabsController.tabs` pattern).
- `src/swift/app/ApplicationSession+Samples.swift` — assign the two `voiceList` callbacks.
- `src/swift/app/CMakeLists.txt` — add the presenter file (hot).
- `src/ui/shell/samplestudio/Sf2ZonePickerDialog.qml` — NEW `DialogWindow`.
- `src/ui/shell/samplestudio/SampleStudioHost.qml` — zone-picker Loader.
- `CMakeLists.txt` (root) — the QML file (hot).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.
- `src/checks/fixtures/decompproject/samplesources/zones.sf2` — NEW binary equal to
  `soundFontFixture().bytes` (242; throwaway generator, not committed).
- `src/checks/editorqml/tst_ShellSampleStudioVoice.qml` — NEW.
- `src/checks/editorqml/ShellQmlEntries.swift` — `shell-sample-studio-voice` entry (fixtures:
  the `shell-sample-studio` set + `samplesources/zones.sf2`); append `samplesources/zones.sf2`
  to `textContrastEntries`' `fixtureFiles`.
- `src/checks/editorqml/tst_TextContrast.qml` — extend `auditSampleStudio` to the zone picker.
- `src/checks/CMakeLists.txt` — the new tst file.
- Ledger `proof.soundfont.txt` A034.

# Prerequisites

253 (workflow, host, dialog, lanes), 242 (`Sf2Reader`, `Sf2ZonePickerModel`, fixture), 247
(`SampleReopen`, `SampleSidecar`), 248 (`readCommittedSample`, update commit).

# Interface contract

- `SampleStudioWorkflow.requestImport(slot:)` with `slot ≥ 0`: same gates plus a bound,
  not-loading voice-list session; records the destination slot; destination ADSR = the slot's
  voice envelope unless its macro is CGB (`VoiceListSemantics.macroIsCgb`); cleared when a new
  flow starts (fork: flows are exclusive).
- `requestEdit(slot:)`; SF2: `zonePickerOpen` (tracked), `zonePicker() -> Sf2ZonePickerPresenter`,
  `acceptZone()`, `cancelZone()`.
- After a successful commit and 215's catalog refresh, an import with a destination slot
  assigns through `voiceList.applyVoiceEdit(slot:voice:)` with the fork keep/new-voice rule
  and `VoiceListSemantics.defaultAdsr(voiceList.adsrDefaults, macro:
  BankVoiceMacro.directSound, symbol:)`, then `voiceList.revealSlot(slot:)`; an assignment
  conflict shows the alert "Sample" with the conflict message (sample stays registered).
  Edits never assign.
- `Sf2ZonePickerPresenter`: tracked `filter`, `canAccept`, `rows` (group rows unselectable,
  zone rows carry `zoneIndex` + six column strings), `select(row:)`, title/placeholder/column
  titles from the model.
- `Sf2ZonePickerDialog.qml`: `DialogWindow` (`src/ui/shell/DialogWindow.qml`, the base Settings uses: native `Qt.Dialog` window with the platform open animation, focus return to `transientParent`, `present()` to open, Escape → `close()` unless `escapeCloses: false`; do not redeclare `flags`, the focus-return handler or an Escape shortcut), `Qt.ApplicationModal`, 60 × 40
  `baseFontPx` initial size, search field, header + rows (groups expanded, indented zone
  rows), OK (enabled by `canAccept`) / Cancel; palette pairs only.

# Implementation steps

1. Workflow routes, SF2 branch, edit branch, assignment; callbacks; zone presenter + QML.
2. Fixture + entry + `tst_ShellSampleStudioVoice.qml` journeys: select a DirectSound slot →
   "+" → `hires_tone.wav` → editor shows "Use destination voice ADSR" checked → commit →
   the slot's sample is the new symbol, dirty bank, one undo restores the old symbol while
   the WAV/`.inc` stay; a CGB-slot import creates a DirectSound voice with default envelope;
   "✎" on the new sample → "Edit Sample — <name>", read-only name, provenance params restored
   (e.g. the dragged loop start), "Save Sample" rewrites the WAV only (`.inc` bytes equal),
   no bank edit or undo entry; "✎" after touching the source file → committed-WAV fallback and
   the sidecar removed on save; "✎" on a non-project symbol → the fork alert; Tools → .sf2 →
   zone picker title/columns, filter "pad" leaves one zone, OK disabled on a group row,
   accept zone 0 → editor source line "16-bit SoundFont zone …" (A034).
3. `deno task bridge:baseline`; contrast audit; ledger edit (delete the soundfont ledger if
   closed).

# Acceptance predicate

From a voice slot the user creates or edits a sample, the created sample is assigned as one
undoable bank edit (undo keeps the sample), edits reopen from provenance or fall back to the
committed WAV and save without a bank edit, and SoundFont sources go through the zone picker.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-sample-studio --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-voicegroup --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-text-contrast --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

`--filter shell-sample-studio` runs all three sample-studio entries; `shell-voicegroup`
guards the existing VoiceEditor journeys (the "+"/"✎" buttons' size/visibility pins).

# Controller verification

Capture the mounted zone picker for `zones.sf2` and the fork `Sf2ZonePicker` for the same
file (reference build `build-asan/porydaw.app`, `capture-macos-app-window` skill); compare
columns, grouping, labels and relative sizes. Run the verification.md Sample-Studio journey
once by hand on a real pret project (import each format → edit → audition → commit → assign →
save → reopen from provenance → `make` the ROM) and record the result.

# Task-specific constraints

Assignment and edit refresh reuse existing paths only (`applyVoiceEdit`, 248's publication,
215's refresh) — no second history authority or refresh path. `VoiceListController.swift` and
`VoiceEditor.qml` are not edited.
