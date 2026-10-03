# Task 1 brief — New Song wizard law and controller (pure Swift + bridge)

## Context

File → New Song becomes the fork's blank-mode wizard (spec.md §2). The mount
(task 2) needs a controller with the laws already proven. This task delivers
the pure `NewSongWizardState`, the bridged `NewSongController` owned by
`SongDockController`, and the swiftcore checks for both. The creation
transaction is **not** written here: Finish reuses
`ProjectService.importSong(_:)` with `MidiFile.blankSong()` (spec.md §3).

Pattern source: `src/swift/app/midiimport/MidiImportWizardState.swift` and
`MidiImportController.swift` (blank mode = import mode minus Analysis page,
minus source picker, minus rescale, with an empty suggested label). Mirror
their structure; do not reopen or edit them.

Surface: the wizard's Swift law and lifecycle owner (not yet reachable from
the menu).
Ledger spec: none edited. The serving ledger is
`src/checks/visual/proof.dialogs.txt` (rows A017–A021 close in task 2).
Verify lanes: `swiftcore-projectsession`, `deno task checks:bridge`.
Blocked rows left untouched: all of `proof.dialogs.txt` (A001–A027 unchanged
in this task); every other ledger.

## Exact write set

Production:
- `src/swift/app/newsong/NewSongWizardState.swift` (new)
- `src/swift/app/newsong/NewSongController.swift` (new)
- `src/swift/app/songlist/SongDockController.swift`: add the controller
  ownership only — `@QtIgnored public let newSong = NewSongController()`,
  `public func newSongController() -> NewSongController`, and the
  `attach(dock:session:)` / `install(service:)` / `detach()` hooks beside the
  `midiImport` ones. No create-mode changes here (task 2 owns that cutover).
- `src/swift/app/CMakeLists.txt`: add the two new Swift files to `porydaw_app`.

Checks:
- `src/checks/songlist/NewSongWizardChecks.swift` (new)
- `src/checks/songlist/songlist_service.swift`: one call line
  `runNewSongWizardChecks(report, fixtureRoot:)` inside
  `runSongListServiceChecks`
- `src/checks/CMakeLists.txt`: add `songlist/NewSongWizardChecks.swift` to the
  `checks` target beside `songlist/MidiImportWizardChecks.swift`.

Five files (plus two new): the state/controller pair is one seam; the CMake
and suite wiring is one line each. Over the file cap at an interface boundary,
not by invented fragments.

## Prerequisites

None (producer). Task 2 consumes this contract verbatim.

## Interface contract

`NewSongWizardState` — pure, `Equatable, Sendable`, mirroring the import
state's shape for the shared members (the mounted pages bind these names):

```swift
public struct NewSongWizardState: Equatable, Sendable {
    public private(set) var page = 0                      // 0 Identity, 1 Sound
    public let windowTitle: String                        // "New Song"
    public let identityPlayerNames: [String]
    public private(set) var playerIndex = 0
    public private(set) var label = ""                    // suggested label: empty
    public private(set) var constant = ""
    public var nameHint: String                           // taken → fork text, else ""
    public var identityComplete: Bool                     // name+constant non-empty, name untaken
    public let voicegroupOptions: [String]
    public let canCreateVoicegroup: Bool
    public var voicegroupText: String
    public var volume = 100
    public var reverb = kDefaultReverb
    public var priority = 0
    public var exactGate = true
    public var extendedClocks = false
    public var noCompression = false
    public init(project: SongImportProjectData, takenLabels: Set<String>)
    public mutating func selectPlayer(_ index: Int)
    @discardableResult public mutating func editLabel(_ proposed: String) -> String
    public mutating func editConstant(_ text: String)
    @discardableResult public mutating func next() -> Bool   // refuses at 0 while !identityComplete; caps at 1
    @discardableResult public mutating func back() -> Bool   // refuses at 0
    public func finishPlan() -> Result<SongImportRequest, NewSongFinishRefusal>
}
```

Laws (frozen; spec.md §2 is the authority):
- `next()`: `guard page < 1, identityComplete else { return false }`.
- Name law: `editLabel` delegates to
  `SongListPresenter.acceptSongLabelEdit(previous:proposed:)`; `constant`
  re-derives via `SongCatalog.constantForLabel` until `editConstant`.
- `nameHint`/`identityComplete` use the taken-label set exactly as the import
  state does.
- Voicegroup options: create entry "(create a new voicegroup for this song)"
  first when `canCreateVoicegroup`, then existing display names; initial
  `voicegroupText` = first **existing** voicegroup (never the create entry);
  no existing voicegroups and `canCreateVoicegroup` → the create entry;
  neither → empty.
- `finishPlan()`: requires `page == 1` and `identityComplete`; returns
  `.failure(NewSongFinishRefusal(title: "New Voicegroup", message: "A
  voicegroup named voicegroup_\(<label>) already exists — pick it from the
  list instead."))` when the create entry is selected and
  `project.voicegroupArgs.contains("_" + label)`; otherwise
  `.success(SongImportRequest(label:constant:player:config:createVoicegroup:,
  midi: MidiFile.blankSong()))` with the current Sound-page values
  (`createVoicegroup` true only for the create entry).

`NewSongController` — `@MainActor @QtBridgeable`, mirroring
`MidiImportController`'s lifecycle/gates minus picker/analysis:

```swift
@QtTracked public var wizardOpen = false
@QtTracked public var busy = false
@QtTracked public var page = 0
@QtTracked public var windowTitle = ""          // published from state
@QtTracked public var label = ""
@QtTracked public var constant = ""
@QtTracked public var nameHint = ""
@QtTracked public var identityComplete = false
public var identityPlayers: [String] = []
@QtTracked public var playerIndex = 0
public var voicegroupOptions: [String] = []
@QtTracked public var voicegroupText = ""
@QtTracked public var volume = 100
@QtTracked public var reverb = kDefaultReverb
@QtTracked public var priority = 0
@QtTracked public var exactGate = true
@QtTracked public var extendedClocks = false
@QtTracked public var noCompression = false
@QtTracked public var warningTitle = ""         // interim, see constraints
@QtTracked public var warningMessage = ""
@QtIgnored func attach(dock: SongDockController, session: ApplicationSession)
@QtIgnored func install(service: ProjectService)
@QtIgnored func detach()
public func requestNewSong()
public func selectPlayer(index: Int)
public func editLabel(text: String) -> String   // returns the accepted text (fold law)
public func editConstant(text: String)
public func changeVoicegroupText(value: String)
public func changeVolume(value: Int); changeReverb(value: Int); changePriority(value: Int)
public func changeExactGate(value: Bool); changeExtendedClocks(value: Bool); changeNoCompression(value: Bool)
public func next(); public func back(); public func finish(); public func cancel()
```

- `requestNewSong()`: `guard canIntake` (spec.md §2 intake gate, identical
  predicates to `MidiImportController.canIntake`); `busy = true`; Task reads
  `service.importProjectData()` (players fallback to `MUSIC_PLAYER_BGM`
  already handled there), builds the state with
  `dock?.presenter.registeredLabels() ?? []`, publishes, `wizardOpen = true`;
  failures go to `session?.operationFailed`.
- `finish()`: `guard !busy, wizardOpen, let state, let service`; close the
  wizard (`wizardOpen = false`), `busy = true`, run `finishPlan()`; a refusal
  publishes `warningTitle`/`warningMessage` (interim channel) and **reopens
  the wizard** (fork: Finish refuses, wizard stays); success runs
  `service.importSong(request)` in a Task and applies spec.md §4:
  `dock?.publishSongs(songs)`, `session?.statusMessage("Created and
  registered \(label) (song ID \(id))")`, and — only when
  `request.createVoicegroup` — `await session?.refreshVoicegroupCatalog()`
  then `session?.openSongFromDock(label: newTab: true)`; on error,
  `dock?.publishSongs` retry (badge) + `session?.operationFailed`.
- `cancel()`/`detach()`: mirror `MidiImportController` (cancel in-flight task,
  clear state).

## Implementation steps

1. Write `NewSongWizardState` with the laws above; no I/O, no Qt types.
2. Write `NewSongController` mirroring `MidiImportController`'s
   publish/change/task patterns (`change { }` helper shape) with the deltas:
   no picker, no analysis members, no rescale, empty suggested label,
   finish-rejection reopens the wizard.
3. Wire ownership into `SongDockController` exactly like `midiImport`
   (attach/install/detach).
4. Add both files to `src/swift/app/CMakeLists.txt`.
5. Write `NewSongWizardChecks.swift` (below) and register it in the suite and
   `src/checks/CMakeLists.txt`.

Edge cases the checks must pin: Next refuses on empty name, taken name, empty
constant; taken-name hint text; constant auto-derivation and its
sticky-after-edit behavior; Sound defaults; create-entry default-avoidance;
finish refusal text; finish success carries `MidiFile.blankSong()` (compare
`encoded()` bytes) and the chosen config/player.

## Acceptance predicate

The state laws and the finish plan hold exactly as specified, and the
controller surface passes the bridge guard.

```sh
deno task checks --filter swiftcore-projectsession --verbose
deno task checks:bridge
deno task proof check --executed
```

Coverage: `swiftcore-projectsession` runs the new `NewSongWizardChecks` inside
the `songlist_service` suite (the same lane that runs
`MidiImportWizardChecks` and `SongImportChecks`) and re-runs the neighboring
songlist suites to prove no regression; `checks:bridge` validates the new
`@QtBridgeable` surface (no unobserved signals); `proof check --executed`
proves no ledger regressions (no ledger is edited here).
Gaps: the mounted QML behavior is task 2's `shell-new-song-wizard` lane; the
commit journey is task 3's `shell-new-song-commit` lane. Neither is claimed
here.

Implementer runs all three; controller re-runs the first after review.

## Task-specific constraints

- Do not edit `MidiImportWizardState.swift`, `MidiImportController.swift` or
  any import-wizard file.
- Do not add a signal `warningRequested(title:message:)` yet: the bridge guard
  rejects signals without an observing QML consumer (task-232/233 precedent).
  Ship the interim `warningTitle`/`warningMessage` tracked properties; task 2
  replaces them with the signal + host `Connections` and deletes the interim
  pair.
- Do not touch `ApplicationSession*.swift`. The only session calls are the
  existing `statusMessage`, `operationFailed`, `refreshVoicegroupCatalog`,
  `openSongFromDock`, `saveInProgress` members already used by the import
  controller.
- No new transaction code: Finish goes through `importSong`; if a needed
  refusal seems missing from it, stop and report — do not fork the order.
