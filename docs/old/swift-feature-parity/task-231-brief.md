# Task 231 brief — the import transaction: fork write order, refusal taxonomy, partial success

# Context

The fork's import commits through `ProjectIo::createSong`
(`fceecd88:src/project/projectio.cpp:318-383`). It first runs
`writeNewSongFiles`, which refuses an existing `.mid`, optionally creates the
voicegroup file and include line, writes the MIDI, and writes the song flags.
It then runs `SongRegistry::registerSong`, which returns the song ID, and
refreshes the project snapshot. When the import creates a voicegroup, it also
refreshes the voicegroup catalog. The first failure stops the sequence and
earlier writes stay in place (`:318-321`). The UI reports the failure
(`workspaceui_project.cpp:380-382`). A stray `.mid` or a partial registration
stays behind, and File → Register Song can retry it
(`spec.md` § Onboarding and project writes).

Swift has each writer: `MidiCfg.writeSongFlags`, `SongFlags.merge`,
`ProjectStore.registerSong`, `ProjectService.createVoicegroup`,
`ProjectFileStore.write` and `MidiFile.encoded()`. Only the copy-from-current
`ProjectService.createSong(label:from:)` (task 171) composes them. No API
creates a song from supplied MIDI with the wizard's choices.

This task is a producer. Its consumer is task 232, which calls
`importProjectData()` on source intake and `importSong(_:)` on Finish.

Surface: the Import MIDI wizard's Finish commit and its project-data feed
(mounted by task 233).
Ledger spec (read-only here): `src/checks/onboardcheck/proof.import.txt`
A050/A051 (refusal writes nothing) and the fork write-order clauses above.
Rows close in 233/234.
Verify lane: `deno task checks --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: all rows. The `project/proof.iomutations.txt`
creation rows that task 171 owns are also left untouched.

# Exact write set

- `src/swift/app/ProjectService+Import.swift` (new): two request/response
  types and two service methods.
- `src/swift/app/CMakeLists.txt`: add the file after
  `ProjectService+Bank.swift`. **Shared** with tasks 230/232 and task 215.
- `src/checks/songlist/SongImportChecks.swift` (new): transaction predicates.
- `src/checks/songlist/songlist_service.swift`: one call,
  `runSongImportChecks(report, fixtureRoot:)`, in `runSongListServiceChecks`.
- `src/checks/CMakeLists.txt`: add the check file beside
  `songlist/SongDebugLayoutChecks.swift`. **Shared** with tasks 230/232 and
  task 215.

# Prerequisites

None for the interface. Task 215's
`ApplicationSession.refreshVoicegroupCatalog()` is consumed by task 232, not
here. `ProjectService+Bank.swift` (task 215 edits its `voicegroupCatalog`
guard) is called but not edited.

# Interface contract

```swift
public struct SongImportProjectData: Equatable, Sendable {
    public var players: [MusicPlayer]        // snapshot table order
    public var voicegroupArgs: [String]      // "_name" args, store order
    public var canCreateVoicegroup: Bool     // sound/voicegroups/ is a directory
}
public struct SongImportRequest: Sendable {
    public var label: String
    public var constant: String
    public var player: String
    public var config: SongConfig            // complete; flags = SongFlags.merge(config)
    public var createVoicegroup: Bool        // config.voicegroupArgument == "_" + label
    public var midi: MidiFile                // already prepared (task 230 pipeline)
}
extension ProjectService {
    public func importProjectData() async throws -> SongImportProjectData
    public func importSong(_ request: SongImportRequest) async throws -> Int  // song ID
}
```

- `importProjectData()` takes `players` from `snapshot.players`. When the
  snapshot has no players, it uses `[MusicPlayer(name: "MUSIC_PLAYER_BGM",
  number: 0, trackCount: -1)]` (fork `projectDataFrom` fallback, `:67-69`).
  `canCreateVoicegroup` mirrors fork `projectio.cpp:677-678`:
  `sound/voicegroups` exists as a directory under the root.
- `importSong` runs this fixed order. Steps 1–4 are refusals and write
  nothing:
  1. `isValidSongLabel(label)`, otherwise "Invalid song label: X." (the
     existing text). The label is **not** normalized: the wizard already
     applied the name law.
  2. `<root>/sound/songs/midi/<label>.mid` must not exist. Otherwise it throws
     the fork text "MIDI file already exists: <path>" (`:326-328`).
  3. No store song has this label. Otherwise it throws "A song named X
     already exists." (task 171/210 stray parity).
  4. When `createVoicegroup` is set, call the existing
     `createVoicegroup(name: label, copyFromFile: "", copySectionLabel: "")`.
     Its name, collision and dummy-template behavior applies unchanged. Its
     refusals occur before its own writes.
  5. Write the MIDI bytes (`midi.encoded()`) with `ProjectFileStore.write`.
  6. Call `MidiCfg.writeSongFlags(midiDir:label:flags: SongFlags.merge(config))`.
  7. Call `store.registerSong(label:constant:player:)`, which returns the song ID.
  8. Set `snapshot = try await store.snapshot()`.
  Every error is wrapped by `projectFailure`, as in the sibling methods. A
  failure in steps 4–7 leaves the earlier writes in place and adds no
  rollback.

# Implementation steps

1. Add the file and the two methods. Reuse `requireStore`, the existing
   `ProjectServiceError.operationFailed`, `isValidSongLabel`,
   `createVoicegroup`, `SongFlags.merge`, `MidiCfg.writeSongFlags` and
   `store.registerSong`. Do not add a second voicegroup writer or MIDI writer.
2. Write the `SongImportChecks.swift` predicates. Stage each case in its own
   `stageTestProject(in: fixtureRoot, projectName: "swiftcore-import-<case>")`.
   Use independent literals, and fingerprint the unchanged files with a local
   FNV or `Data` equality.
   - Happy path with an existing voicegroup:
     - The returned ID equals the pre-import `registrationPlan` song ID.
     - The written `.mid` decodes to the request's division and chunk count.
     - The `midi.cfg` line for the label equals `SongFlags.merge(config)`,
       for example `-E -R50 -G_test_vg -V100`.
     - `songs()` lists the label as registered with no gaps.
   - Create voicegroup:
     - `sound/voicegroups/<label>.inc` exists with the `voicegroup_<label>`
       header.
     - `voice_groups.inc` gained the include.
     - `voicegroupArgs()` contains `_<label>`.
     - The cfg carries `-G_<label>`.
   - An existing `.mid` holds foreign bytes, and `createVoicegroup` is set:
     - The call throws the fork text.
     - The foreign bytes are preserved exactly.
     - `midi.cfg` and `voice_groups.inc` are byte-identical.
     - No `<label>.inc` exists. This proves step 2 runs before step 4.
   - A registered-label collision and a voicegroup-exists collision each
     throw and write nothing.
   - Partial success: before the import, make `include/constants/songs.h`
     read-only (POSIX 0o444).
     - The call throws.
     - The `.mid` and the `midi.cfg` line exist.
     - `songs()` lists the label with `registrationIncomplete`.
     - After the permissions are restored, `songRegistrationPlan` and
       `registerSong` complete the entry, and a second `registerSong` makes
       no change (idempotent retry).
   - Flag-write failure: `midi.cfg` is read-only.
     - The call throws.
     - The `.mid` exists.
     - The label is listed as unregistered.
   - `importProjectData` on the read-only decomp fixture root:
     - Players are in table order, `MUSIC_PLAYER_BGM` (trackCount 16) first,
       and include `MUSIC_PLAYER_SE_1TRK` with trackCount 1.
     - `canCreateVoicegroup` is true.
     - The args include `_fixture_rich`.
3. Restore every permission you change before the case returns, including on
   failure paths.

# Acceptance predicate

`importSong` writes in the fork's order and refuses with the fork's texts
before any write. It leaves earlier writes in place on later failures, and
a retried Register Song completes those. `importProjectData` feeds players,
args and the per-file capability. All of this is proven against real
read-only files in the projectSession lane.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

Coverage: the lane runs every predicate above and the existing song
service/registration/deletion predicates. Gap: the mounted Finish path and
the refresh of the Songs dock and catalog are covered by tasks 233/234.

# Task-specific constraints

- Do not route through or change `createSong(label:from:)`. New Song keeps
  its task-171 contract.
- No transaction abstraction, rollback or temporary directory. Freezing the
  fork order is the requirement (`plan.md` Onboarding prerequisite).
- A refusal must not create directories or touch `midi.cfg`, `songs.mk` or any
  registration file.
- `createVoicegroup` reopens the project and replaces the service's store.
  After step 4, get a new `requireStore()` for steps 7–8. Never register
  through the store reference that existed before the reopen.
- `MusicPlayer` (`src/swift/project/SongCatalog.swift`) must be `public`
  with public members for the struct above. If it is not, widening its
  access is the only permitted `PorydawProject` edit. Add the file to the
  write set and report it.
