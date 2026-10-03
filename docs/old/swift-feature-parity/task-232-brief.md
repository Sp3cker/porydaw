# Task 232 brief — the Import MIDI wizard's Swift owner: state laws, controller, one song-name law

# Context

The fork's wizard gathers its choices on three pages and commits once
(`fceecd88:src/ui/newsongwizard.cpp`, `workspaceui_samples.cpp:46-90`).

- **Source intake** (`runMidiImport:46-72`):
  - The intake runs only while the project is open and no project operation
    or dialog is in flight.
  - The picker titled "Import MIDI" opens with filter "MIDI (*.mid)" at the
    `lastImportDir` preference, which defaults to the home directory.
  - A read failure shows a warning titled "Import MIDI" with "Cannot open
    MIDI file: <path>" (`smf.cpp:262-267`), or with the codec error.
  - `lastImportDir` is stored **only after a successful read**.
- **Analysis page** (`AnalysisPage:288-535`):
  - A role combo ("The song will be used as:") shows `playerRoleName(name,
    false)`. It stays in sync with the identity player combo in both
    directions (`:167-172,394,410-416,433`).
  - The wording comes from the task 230 summary.
  - The rescale checkbox appears only when `division % 24 != 0`, and it is
    checked by default (`:340-347`).
  - The "CC commands" table is built once from the opening analysis
    (`:349-391`).
- **Identity page** (`IdentityPage:90-182`):
  - The name field starts with the suggested label. Its placeholder is
    `mus_my_song`.
  - The constant follows `constantForLabel(name)` until the user edits it.
  - Players are shown as `playerRoleName(name, true)`.
  - The page is complete when the name and the constant are both non-empty
    and the name is not taken. A taken name shows the hint "A song named %1
    already exists.".
- **Sound page** (`SoundPage:184-286`):
  - The editable voicegroup combo lists "(create a new voicegroup for this
    song)" first, when the project can create one. The default is the first
    existing voicegroup.
  - Default values: volume 100, reverb 50, priority 0, exact gate on,
    `-X` off, `-N` off.
  - The cfg is built at `:254-266`.
  - `validatePage` refuses a new voicegroup whose `_<label>` already exists.
    It shows the warning titled "New Voicegroup": "A voicegroup named
    voicegroup_%1 already exists — pick it from the list instead."
- **Finish** (`submitCreateSong:74-90`):
  - The wizard closes first.
  - An emission failure shows a warning titled "Import MIDI" with the error,
    and nothing is written.
  - Otherwise the commit runs. On success the status reads "Created and
    registered %1 (song ID %2)" (`workspaceui_project.cpp:580-594`).
  - When a voicegroup was created, the catalog refreshes and the song opens
    in a new tab (`:195-204`). Otherwise the song only appears in the Songs
    list.

The name law is decided here. The fork's `LowercaseNameValidator`
(`:78-88,102-105`) folds the **whole edit** to lowercase, then accepts it or
rejects it as a unit. Pasting "mus 3!" into an empty field leaves the field
empty (onboard A065). Task 210's `normalizeSongLabel` filters character by
character, and `SongConfirmDialog` uses it. Its keystroke results are the
same as the fork's, but a paste diverges. This task adopts the fork's edit
law for both name fields, so one law serves both. Task 210's keystroke
journeys stay valid.

Producer/consumer:
- Consumes task 230 (`MidiImport` pipeline and helpers,
  `ImportAnalysisSummary`).
- Consumes task 231 (`importProjectData`, `importSong`).
- Consumes task 215 (`ApplicationSession.refreshVoicegroupCatalog() async ->
  Bool`).
- The consumer is task 233, which mounts the QML and routes File → Import
  MIDI.

Surface: the Import MIDI wizard's behavior, and the New Song name field's
paste law.
Ledger spec (read-only here): onboard A048–A078 and dialogs A022–A027. They
close in 233/234.
Verify lanes: `deno task checks --filter swiftcore-projectsession --verbose`,
`deno task checks:shell --filter shell-songs --verbose` (New Song
regression), `deno task checks:bridge`.
Blocked rows left untouched: all rows. New Song keeps its task-171 prompt.
The fork's blank-mode wizard (dialogs A017–A021) is not ported.

# Exact write set

Production:
- `src/swift/app/midiimport/MidiImportWizardState.swift` (new): the pure
  wizard value type.
- `src/swift/app/midiimport/MidiImportController.swift` (new): the bridged
  controller and its `ImportControllerRow` row class.
- `src/swift/app/songlist/SongDockController.swift`: owns the controller and
  forwards its lifecycle. Adds `publishSongs(_:)`.
- `src/swift/app/songlist/SongListPresenter.swift`: adds the edit law and
  `registeredLabels()`, and removes the instance `normalizeSongLabel(text:)`.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml`: the name field
  switches to the edit law.
- `src/swift/app/CMakeLists.txt`: adds the two new files. **Shared** with
  230/231/215.

Checks:
- `src/checks/songlist/MidiImportWizardChecks.swift` (new).
- `src/checks/songlist/songlist_service.swift`: one call.
- `src/checks/CMakeLists.txt`: one source line. **Shared** with 230/231/215.

Over the three-file cap: one interface (the controller contract) with one
verification surface. The name-law migration moves every caller of the law
together.

# Prerequisites

- Tasks 230 and 231 (the interfaces above).
- Task 215 landed (`refreshVoicegroupCatalog`).

# Interface contract

`SongListPresenter`:
- `@QtIgnored public nonisolated static func acceptSongLabelEdit(previous:
  String, proposed: String) -> String`. Let `folded =
  proposed.lowercased()`. Return `folded` when it is empty or fully matches
  ASCII `^[a-z_][a-z0-9_]*$`. Otherwise return `previous`.
- A public instance twin for QML: `acceptSongLabelEdit(previous:proposed:)`.
- `@QtIgnored func registeredLabels() -> Set<String>` over `allListings`
  where `registered` is true. This is the same set that `songLabelTaken`
  uses.
- Delete the instance `normalizeSongLabel(text:)`. Keep the static one for
  `ProjectService.createSong`.

`public struct MidiImportWizardState: Equatable, Sendable` (pure):
- `init(source: MidiFile, sourceFileName: String, project:
  SongImportProjectData, takenLabels: Set<String>)`.
- Read-only members:
  - Page: `page: Int` (0 analysis, 1 identity, 2 sound) and `windowTitle`
    ("Import MIDI — <file>").
  - Players: `analysisPlayerNames: [String]`, `identityPlayerNames: [String]`,
    `playerIndex`.
  - Analysis: `summary: ImportAnalysisSummary`, `offersRescale`,
    `controllerRows: [ImportControllerRowValue]`.
    `ImportControllerRowValue` holds `controller` ("CC n"/"XCMD"), `function`,
    `events`, `inGame` ("Yes"/"No"/"Needs review"; `importSupportText:34-45`)
    and `needsAttention`.
  - Identity: `label`, `constant`, `nameHint`, `identityComplete`.
  - Sound: `voicegroupOptions`, `canCreateVoicegroup`.
- Mutable members:
  - `rescale` (defaults to `offersRescale`).
  - `voicegroupText` (defaults to `voicegroupOptions[canCreate && count > 1 ?
    1 : 0]`).
  - `volume = 100`, `reverb = kDefaultReverb`, `priority = 0`,
    `exactGate = true`, `extendedClocks = false`, `noCompression = false`.
- Mutating methods:
  - `selectPlayer(_ index: Int)`: out-of-range indices are ignored.
    Recomputes `MidiImport.analyze(source, trackBudget:
    trackLimit(playerTrackCount:), playerName:)` and the summary.
  - `editLabel(_ proposed: String) -> String`: applies the edit law. It
    re-derives the constant while `!constantEdited`, then returns the
    accepted text.
  - `editConstant(_ text: String)`: sets `constantEdited`.
  - `next() -> Bool`: 0→1 always; 1→2 only when `identityComplete`.
  - `back() -> Bool`: steps back only when the page is greater than 0.
- `func finishPlan() -> Result<ImportFinishPlan, ImportFinishRefusal>`:
  - Available only on page 2 while `identityComplete`.
  - `ImportFinishRefusal` has `title` and `message`. It carries the fork's
    New Voicegroup text when a new voicegroup is chosen and
    `"_" + label` is in the args.
  - `ImportFinishPlan` has `label`, `constant`, `player` (symbol), `config:
    SongConfig`, `createVoicegroup`, `rescale` (`offersRescale && rescale`)
    and `extendedClocks`.
  - The config's `voicegroupArgument` is `"_" + label` when creating.
    Otherwise it is
    `VoiceListSemantics.voicegroupArg(fromDisplay: trimmed, knownArgs:)`.
  - `reverb` is always explicit (the fork writes `-R50`), and `rawFlags` is
    `SongFlags.merge(config)`.

`@MainActor @QtBridgeable public final class MidiImportController`, owned by
`SongDockController` (`public func midiImportController() ->
MidiImportController`):
- Tracked or supported members, declared in the class body:
  - `wizardOpen`, `busy`, `page`, `windowTitle`, `startFolder` (file URL
    string).
  - `analysisPlayers`, `identityPlayers`, `playerIndex`.
  - The nine summary strings, as `fileTracksText`…`controllerText`.
  - `offersRescale`, `rescale`, `controllerRows:
    QListModel<ImportControllerRow>`, `hasControllerRows`.
  - `label`, `constant`, `nameHint`, `identityComplete`.
  - `voicegroupOptions`, `voicegroupText`, `volume`, `reverb`, `priority`,
    `exactGate`, `extendedClocks`, `noCompression`.
- `@QtSignal func sourcePickerRequested()` and `@QtSignal func
  warningRequested(title: String, message: String)`.
- Slots:
  - `requestImport()`
  - `chooseSource(fileUrl: String)`
  - `selectPlayer(index:)`, `setRescale(value:)`
  - `editLabel(text:) -> String`, `editConstant(text:)`
  - `changeVoicegroupText(value:)`, `changeVolume(value:)`,
    `changeReverb(value:)`, `changePriority(value:)`,
    `changeExactGate(value:)`, `changeExtendedClocks(value:)`,
    `changeNoCompression(value:)`
  - `next()`, `back()`, `finish()`, `cancel()`
- Every mutation goes through the state and then republishes. Rows use the
  existing `QListModelSync` equality-gated pattern.

# Implementation steps

1. Add the name law to the presenter. In `SongConfirmDialog`'s
   `onTextChanged`, call
   `acceptSongLabelEdit(controller.newSongLabel, text)`. When the edit is
   rejected, restore the previous text and move the cursor back by the
   rejected insertion, clamped to the text bounds. When the edit only folds
   case, keep the cursor. Then write `controller.newSongLabel`.
2. Write `MidiImportWizardState` with the laws above. It performs no I/O and
   uses no Qt.
3. Write `MidiImportController`:
   - `requestImport`: returns silently unless all of these hold:
     `session.projectOpen`, the service is installed, `!busy`,
     `!wizardOpen`, the dock is not `busy`, and
     `!session.saveInProgress`. When they hold, it refreshes `startFolder`
     from `PreferencesStore().string(key: "lastImportDir", fallback:
     NSHomeDirectory())` and emits `sourcePickerRequested`.
   - `chooseSource`:
     1. Re-check the gates.
     2. Parse the URL, which must be a non-empty file URL, as in
        `ShellPresenter.chooseProject`.
     3. Read the file and decode it with `MidiFile.decode`. On failure, emit
        `warningRequested` with the fork title and message, and store no
        preference.
     4. On success, store `lastImportDir` (the parent directory path) and
        `synchronize()`.
     5. Run `importProjectData()` in the `operation` Task, with a stale guard
        (`service ===` the captured service, not cancelled). A failure goes
        to `session.operationFailed`.
     6. Build the state with `takenLabels: dock.presenter.registeredLabels()`,
        publish it, and set `wizardOpen = true`.
   - `finish`:
     1. Compute `finishPlan()`. A refusal emits `warningRequested` and keeps
        the wizard open on the Sound page.
     2. Otherwise set `wizardOpen = false`.
     3. Run `MidiImport.prepareImportedSong`. If it throws, emit
        `warningRequested("Import MIDI", description)` and stop, with no
        writes.
     4. Otherwise set `busy = true` and, in a Task, call
        `service.importSong(SongImportRequest)`.
     5. On success, call `dock.publishSongs(try await service.songs())`.
        Then emit `session.statusMessage(message: "Created and registered
        <label> (song ID <id>)")`. When a voicegroup was created, `await
        session.refreshVoicegroupCatalog()` and then
        `session.openSongFromDock(label:newTab: true)`.
     6. On failure, call `session.operationFailed(message:
        String(describing: error))`. Then publish refreshed songs,
        best-effort, so that a stray or partial registration shows its
        retry badge. Also refresh the catalog when a voicegroup creation
        was requested.
     7. Set `busy = false` after every path.
     8. Apply the stale guard after each await.
   - `cancel()`: closes the wizard and clears the state. It writes nothing.
4. In `SongDockController`:
   - `attach` passes the dock and the session to the controller.
   - `install` calls `midiImport.install(service:)`, which cancels the
     operation, closes the wizard and resets its state.
   - `detach` calls `midiImport.detach()`.
   - `publishSongs(_:)` performs `presenter.setSongs`,
     `session.refreshSongLabels` and `syncSelection`. Make
     `acceptConfirmation` use it (Extract Method, same behavior).
5. Write the checks in `MidiImportWizardChecks.swift`
   (`runMidiImportWizardChecks(report, fixtureRoot:)`):
   - Edit-law rows:
     - `("", "MUS_Loud_3")` → "mus_loud_3"
     - `("", "mus 3!")` → ""
     - `("mu", "mu$")` → "mu"
     - `("mu", "9mu")` → "mu"
     - `("abc", "")` → ""
   - State rows over `test_midis/external_import.mid` with literal project
     data: players BGM(16), SE1(3), SE_1TRK(1); args `["_fixture_alt",
     "_fixture_rich"]`; `canCreate` true; taken `{"mus_route101"}`.
     - Opening state: title, label "mus_external_import", constant
       "MUS_EXTERNAL_IMPORT", `offersRescale` and `rescale`, both combos'
       first entries, and voicegroup default "fixture_alt".
     - Player sync and the SE_1TRK mute summary.
     - The taken hint blocks `next`.
     - Constant ownership after `editConstant`.
     - Page bounds.
     - Sound defaults.
     - The New Voicegroup refusal text for label "fixture_alt".
     - The plan flags `["-E", "-R50", "-G_fixture_alt", "-V100"]`.
     - The create plan's `_mus_external_import`.
     - A division-24 in-memory source does not offer a rescale.

# Acceptance predicate

The wizard's laws reproduce the fork clauses cited above in pure Swift
predicates, and the controller composes them with tasks 230/231/215 through
bridged state that QML can bind. The New Song field applies the fork's edit
law with its existing keystroke journeys unchanged.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-songs --verbose
deno task checks:bridge
deno task proof check --executed
```

Coverage:
- projectSession runs the law and state predicates.
- shell-songs proves that the New Song prompt still folds, filters and
  blocks taken names through real keystrokes.
- The bridge guard covers the new bridged members.

Gap: the controller's async intake, the picker and Finish are proven on the
mounted surface in tasks 233/234.

# Task-specific constraints

- Keep `ApplicationSession*.swift` and `ShellPresenter*.swift` unchanged. The
  controller reaches the session only through existing internal APIs:
  `operationFailed`, `statusMessage`, `refreshSongLabels`,
  `openSongFromDock`, `refreshVoicegroupCatalog`, `projectOpen` and
  `saveInProgress`.
- Do not add a test-only accessor. Checks drive the pure state; the
  controller is proven through QML in 233/234.
- The controller never retains a `MidiFile` after `cancel`, `install`,
  `detach` or a completed Finish.
