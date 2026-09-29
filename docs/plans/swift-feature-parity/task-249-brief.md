# Task 249 brief — Sample Studio editor presenter: parameters, dialog-local undo, rate commit, naming, readouts

# Context

Spec.md: rate commit on preset/Return/focus-out; root/fine tuning, normalize controls, ROM
cost/duration and warnings available; a **dialog-local parameter undo history** (one drag or
merged spin gesture per entry; undo/redo restores the rendered result) that is not song
history; sanitized/prefilled names validated against symbols and WAV/BIN paths; existing-sample
edits keep their name. Fork owner: `SampleEditorDialog` (`src/ui/sampleeditordialog.cpp`)
minus its waveform, loop/pitch tools and audition strip (250/251/252). This task builds the
QtBridge presenter the QML dialog (253) binds to; it owns the `SampleDocument` and the undo
stack every other editor object edits through.

Surface: `SampleStudioPresenter` (SA03 editor state).
Ledger spec and rows (→ MATCHED; widget-lookup rows → RETIRED-REPRESENTATION "QWidget
findChild lookup; the QML dialog binds presenter properties"; setup rows per the P4
scaffolding rule):
- `proof.editor.txt`: pipelinePrefillCollision A001–A012 (NATIVE A006–A010, A012 ported;
  A005 retired), pipelinePreparedDefaults A013–A017 (A014 retired; NATIVE A016 ported),
  pipelineKeyOverride A018–A021 (A019 retired), pipelineRateCommit A025–A032 (A026 retired),
  pipelineCropNormalize A033–A036 (A034 retired), editorUndo A089–A095 (A092 retired; NATIVE
  A093 ported), editorCommit A106–A115 (A109 retired; NATIVE A115 ported).
- `proof.integration.txt` sidecarEditDialog A060–A064 (NATIVE A061, A062, A064 ported).
Verify lane: `samplecheck` (MainActor presenter predicates).
Blocked rows left untouched: editor A022–A024, A037–A088, A096–A105, A116–A130 (250–253);
integration ledger closes and is deleted here if zero open rows remain.

Oracles: `git show fceecd88:src/ui/sampleeditordialog.{h,cpp}` — `sourceLine` 40–77,
`parseMidiKey` 81–99, `MidiKeySpinBox` 103–116, `SampleParamsCommand` 118–166, constructor
rate combo 370–396 and `kGbaMixRates`, spins 266–276/308–309/350–356/465–486, normalize
488–501, add button 510–520, `setEditTarget` 554–563, `applyParamsFromUi` 600–626,
`commitParams`/`applyParamsExternal`/`syncUiFromParams` 628–673, `refreshOutputs` 675–756
(summary/tech/gain/seam text), `validateName` 758–768; `src/ui/workspaceui_samples.cpp`
`validateNewSampleName` and the edit-mode validator. Check oracle: `git show
fceecd88:src/checks/samplecheck/editor.cpp` (pipeline*, editorUndo, editorCommit),
`integration.cpp` 360–385.

# Exact write set

- `src/swift/app/samplestudio/SampleStudioPresenter.swift` — NEW `@QtBridgeable` presenter.
- `src/swift/app/samplestudio/SampleStudioHistory.swift` — NEW dialog-local undo stack.
- `src/swift/app/samplestudio/SampleStudioReadouts.swift` — NEW pure text builders.
- `src/swift/app/CMakeLists.txt` — add the three files (hot).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline` (shared across
  tracks; regenerate, never hand-edit).
- `src/checks/samplecheck/EditorPresenterChecks.swift` — NEW `runEditorPresenterChecks`
  (MainActor).
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledgers `proof.editor.txt`, `proof.integration.txt` (rows above).

# Prerequisites

244 (`SampleDocument`, `SampleEditParams`, `SampleWavWriter`), 246 (`SampleRegistrar.validate/
register` for the commit rows), 247 (`SampleSidecar` params baseline for A060–A064).

# Interface contract

`@QtBridgeable @MainActor public final class SampleStudioPresenter`:

- Swift-only init (`@QtIgnored`): `init(source: ImportedSample, validateName: @escaping
  (String) -> String?)` — validator returns nil when acceptable, else the message.
- Tracked properties (QML reads): `windowTitle` ("Sample Editor" / "Edit Sample — <name>"),
  `sampleName`, `nameReadOnly`, `nameStatus` ("Registers as DirectSoundWaveData_<name>" /
  "Saves over DirectSoundWaveData_<name>'s sample data" / the validator message), `canCommit`,
  `commitLabel` ("Add to Project" / "Save Sample"), `sourceLine`, `sourceFrameCount`,
  `cropStart`, `cropEnd`, `loopOn`, `loopStart`, `loopEnd`, `baseKey`, `baseKeyText`
  ("A3 (57)"), `fineTuneCents`, `rateChoices: [String]` ("Keep source (<rate> Hz)" + the fork
  `kGbaMixRates`), `rateIndex` (0 = keep source, −1 = custom), `rateText`, `normalizeMode`,
  `normalizeChoices` (fork four labels), `gainReadout`, `outputSummary`, `techDetail`,
  `canUndo`, `canRedo`, `renderRevision` (bumps after every render change).
- QML-callable: `setSampleName(_:)`, `setCropStart(_:)`/`setCropEnd(_:)` (merge keys 1/2),
  `setLoopStart(_:)`/`setLoopEnd(_:)` (3/4), `setBaseKeyText(_:)` (fork `parseMidiKey`,
  fallback = current; merge key 5), `setFineTuneCents(_:)` (6), `chooseRate(index:)` (−1),
  `commitRateText(_:)` (Return/focus-out only; unparsable or ≤ 0 → keep source; −1),
  `setNormalizeMode(_:)` (−1), `undo()`, `redo()`, `beginMarkerGesture()`,
  `dragMarkers(cropStart:cropEnd:loopStart:loopEnd:)` (applies live, no entry),
  `endMarkerGesture()` (one entry when changed).
- Swift API (`@QtIgnored`): `document`, `params`, `processed`, `source`;
  `commitParams(_ params: SampleEditParams, mergeKey: Int)` (fork `commitParams`: no-op when
  equal; merge when same non-negative key; a merged run returning to its base drops the entry);
  `applyParamsExternal(_:)` (no entry; used by undo/redo and the edit baseline);
  `setEditTarget(name:)` (read-only name, edit labels/title, validator accepts only that name
  with "the sample keeps its registered name (<name>)." otherwise); `wavBytes() -> Data`;
  `addRenderObserver(_ body: @escaping @MainActor () -> Void)` (called after every
  params/render change, in registration order — 250/251/252 subscribe).
- Exact-pitch law (fork 616–624): `exactPitchOverride = source.exactPitch` only while target
  rate equals the source rate, key equals the source key and fine tune equals the
  spin-rounded source cents (two decimals); otherwise 0.
- Readouts: `SampleStudioReadouts` builds the fork `refreshOutputs` strings verbatim (brief
  line "<s> s · <n> KB|bytes ROM", "Warning: …" lines from source + render warnings, technical
  "Output: …", "Pitch: … at C4 (60) — agbp …, unity … (<name>)", "ROM cost: … — seam amp …,
  slope …[, match …%]", gain "gain x.x dB" / "gain 0.0 dB" when normalize is off); ROM bytes
  `16 + ((size + 3) & ~3)`.

# Implementation steps

1. History (`SampleStudioHistory`: entries of before/after params + merge key; obsolete-entry
   removal) and readouts as pure Swift.
2. Presenter: property sync after every change (`syncUiFromParams` equivalent), render via
   the document, observers.
3. `EditorPresenterChecks.swift` driving only the public presenter API with fork fixtures
   (`preparedSampleWav`, `hiResSampleWav`) and a real `SampleRegistrar.validate` validator
   over a scratch wav2agb project: prefill + collision/fresh/bad-name gates, prepared
   defaults byte-verbatim, key override drops/restores the agbp word, rate typing does not
   re-render until `commitRateText`, crop/normalize, undo counts and full undo equals
   `defaultParams`, commit through `SampleRegistrar.register(…, wavBytes())` with the exact
   `.inc` block and loader bytes == `processed.s8` (A115), edit mode (A060–A064: read-only
   name, commit enabled, sidecar params as baseline with zero undo entries).
4. `deno task bridge:baseline`; ledger edits.

# Acceptance predicate

Driving the presenter reproduces the fork dialog's name gates, defaults, pitch-word law, rate
commit discipline, crop/normalize results, one-entry-per-gesture undo/redo and byte-exact
commit, and edit mode loads provenance params as a baseline.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

Gap: QML binding, Return/focus-out delivery and the mounted commit are 253's journeys.

# Task-specific constraints

The presenter never touches files, audio or the catalog (253's workflow does). Undo here is
dialog-local and never reaches `DocumentSession` history. No hard-coded pixel values (no
geometry in this task). Seam badge text belongs to 250.
